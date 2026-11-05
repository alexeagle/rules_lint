"""API for declaring a Scalafix lint aspect that visits scala_library, scala_binary, and scala test rules.

Scalafix is a linting and refactoring tool for Scala that supports both syntactic and semantic rules.
See https://scalacenter.github.io/scalafix/

Typical usage:

First, fetch scalafix using rules_jvm_external in your MODULE.bazel:

```starlark
maven = use_extension("@rules_jvm_external//:extensions.bzl", "maven")
maven.install(
    artifacts = [
        "ch.epfl.scala:scalafix-cli_2.13.18:0.14.5",
    ],
    lock_file = "@//:maven_install.json",
    repositories = [
        "https://maven.google.com",
        "https://repo1.maven.org/maven2",
    ],
)
use_repo(maven, "maven")
```

Note that scalafix is not binary compatible with its scala meta dependency.
You will likely want to install it in a separate maven hub.

Next, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
load("@rules_java//java:defs.bzl", "java_binary")

java_binary(
    name = "scalafix",
    main_class = "scalafix.cli.Cli",
    runtime_deps = ["@maven//:ch_epfl_scala_scalafix_cli_2_13_18"],
    visibility = ["//visibility:public"],
)
```

Finally, create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint_scala//lint:scalafix.bzl", "lint_scalafix_aspect")

scalafix = lint_scalafix_aspect(
    binary = Label("//tools/lint:scalafix"),
    config = Label("//:.scalafix.conf"),
)
```

## Semantic Mode

Scalafix supports two types of rules:
- **Syntactic rules**: Run on source code without compilation (default)
- **Semantic rules**: Require SemanticDB data from compilation

To enable semantic rules (e.g., OrganizeImports with removeUnused):

1. Enable SemanticDB in your scala_toolchain:
   ```starlark
   scala_toolchain(
       name = "my_toolchain",
       enable_semanticdb = True,
       # Required: scalafix expects SemanticDB on the classpath in sandboxed actions.
       semanticdb_bundle_in_jar = True,
       ...
   )
   ```

2. Create the aspect with semantic=True:
   ```starlark
   scalafix = lint_scalafix_aspect(
       binary = Label("//tools/lint:scalafix"),
       config = Label("//:.scalafix.conf"),
       semantic = True,
   )
   ```

Note: semantic mode requires `semanticdb_bundle_in_jar = True`. Unbundled SemanticDB files
are not available to sandboxed actions, so they cannot be consumed reliably here.

Note: rewrite-only rules emit diffs. The SARIF output uses a generic warning at each diff
hunk start line, which is sufficient for CI but less detailed than the human report.
"""

load("@rules_lint//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "patch_and_output_files", "should_visit")
load("@rules_lint//lint/private:patcher_action.bzl", "patcher_attrs", "run_patcher")
load("@rules_java//java:defs.bzl", "JavaInfo")
load("@rules_scala//scala:semanticdb_provider.bzl", "SemanticdbInfo")

_MNEMONIC = "AspectRulesLintScalafix"

def scalafix_action(ctx, executable, srcs, config, stdout, exit_code = None, args = [], patch = None, classpath = None):
    """Run scalafix as a build action in Bazel.

    Args:
        ctx: an action context or aspect context
        executable: the scalafix java_binary executable
        srcs: A list of Scala source files to lint
        config: The .scalafix.conf configuration file
        stdout: output file for linter results
        exit_code: output file to write the exit code.
            If None, then fail the build when scalafix exits non-zero.
        args: additional command-line arguments to scalafix
        patch: output file for patch (optional). If provided, uses run_patcher for fix mode.
        classpath: For semantic rules - transitive compile classpath (list of jars)
    """
    scala_toolchain = ctx.toolchains["@rules_scala//scala:toolchain_type"]

    action_args = ctx.actions.args()
    action_args.add_all(args)
    action_args.add("--config", config)
    action_args.add("--scala-version", scala_toolchain.scala_version)

    inputs = list(srcs) + [config]
    outputs = [stdout]

    if classpath:
        # Semantic mode: pass classpath and scalac options
        action_args.add("--classpath", ":".join([jar.path for jar in classpath]))
        action_args.add_all(scala_toolchain.scalacopts, before_each = "--scalac-options")
        inputs.extend(classpath)
    else:
        # Syntactic mode: no compilation data needed
        action_args.add("--syntactic")

    # Add source files
    action_args.add_all(srcs, before_each = "--files")

    if patch != None:
        # Use run_patcher for fix mode
        run_patcher(
            ctx,
            ctx.executable,
            inputs = inputs,
            args = action_args,
            files_to_diff = [s.path for s in srcs],
            patch_out = patch,
            tools = [executable],
            stdout = stdout,
            exit_code = exit_code,
            mnemonic = _MNEMONIC,
            progress_message = "Fixing %{label} with Scalafix",
        )
    else:
        # Lint mode with --check
        action_args.add("--check")

        if exit_code:
            # Don't fail scalafix and just report the violations
            command = "{scalafix} $@ >{stdout}; echo $? >" + exit_code.path
            outputs.append(exit_code)
        else:
            # Run scalafix with arguments passed, create empty stdout file on success
            command = "{scalafix} $@ && touch {stdout}"

        ctx.actions.run_shell(
            inputs = inputs,
            outputs = outputs,
            command = command.format(scalafix = executable.path, stdout = stdout.path),
            arguments = [action_args],
            mnemonic = _MNEMONIC,
            tools = [executable],
            progress_message = "Linting %{label} with Scalafix",
        )

def _scalafix_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    files_to_lint = filter_srcs(ctx.rule)

    # Determine if we should use fix mode
    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(_MNEMONIC, target, ctx)
    else:
        outputs, info = output_files(_MNEMONIC, target, ctx)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    # Semantic mode: collect classpath and semanticdb metadata
    classpath = None

    if ctx.attr._semantic and JavaInfo in target and SemanticdbInfo in target and target[SemanticdbInfo].semanticdb_enabled:
        # Access classpath from JavaInfo (like spotbugs)
        classpath = target[JavaInfo].transitive_compile_time_jars.to_list()

        # Ensure the target's own output jar is present so Scalafix can find bundled SemanticDB.
        for jar in [j.class_jar for j in target[JavaInfo].outputs.jars]:
            if jar not in classpath:
                classpath.insert(0, jar)

        semanticdb_info = target[SemanticdbInfo]
        if not semanticdb_info.is_bundled_in_jar and semanticdb_info.target_root:
            fail("Scalafix semantic mode requires semanticdb_bundle_in_jar = True. The SemanticDB target root is not accessible from sandboxed actions.")

    # Human-readable output
    scalafix_action(
        ctx,
        ctx.executable._scalafix,
        files_to_lint,
        ctx.file._config,
        outputs.human.out,
        outputs.human.exit_code,
        ctx.attr._args,
        patch = getattr(outputs, "patch", None),
        classpath = classpath,
    )

    # Machine-readable output (raw for SARIF conversion)
    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    scalafix_action(
        ctx,
        ctx.executable._scalafix,
        files_to_lint,
        ctx.file._config,
        raw_machine_report,
        outputs.machine.exit_code,
        ctx.attr._args,
        classpath = classpath,
    )

    # Convert to SARIF format
    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)

    return [info]

def lint_scalafix_aspect(binary, config, rule_kinds = ["scala_library", "scala_binary", "scala_test", "scala_junit_test"], semantic = False, args = []):
    """A factory function to create a linter aspect.

    Args:
        binary: a scalafix executable, provided as a java_binary target
        config: label of the .scalafix.conf configuration file
        rule_kinds: which [kinds](https://bazel.build/query/language#kind) of rules should be visited by the aspect
        semantic: If True, enables semantic rules (requires SemanticDB from compilation).
            When enabled, the aspect will access classpath and SemanticDB metadata from the target.
            If SemanticDB is not enabled for the target, the aspect falls back to syntactic-only mode.
        args: Additional options to pass to scalafix cli

    Returns:
        An aspect definition for scalafix
    """
    return aspect(
        implementation = _scalafix_aspect_impl,
        attrs = patcher_attrs | {
            "_options": attr.label(
                default = "@rules_lint//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_scalafix": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_config": attr.label(
                default = config,
                allow_single_file = True,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
            "_semantic": attr.bool(
                default = semantic,
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
        toolchains = [
            OPTIONAL_SARIF_PARSER_TOOLCHAIN,
            "@rules_scala//scala:toolchain_type",
        ],
    )
