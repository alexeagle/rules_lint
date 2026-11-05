"""API for declaring a spotbugs lint aspect that visits java_library and java_binary rules.

Typical usage:

First, call the tools.spotbugs module extension to download the jar file.
Alternatively you could use whatever you prefer for managing Java dependencies, such as a Maven integration rule.

Next, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
java_binary(
    name = "spotbugs",
    main_class = "edu.umd.cs.findbugs.LaunchAppropriateUI",
    runtime_deps = [
        "@spotbugs//:jar",
    ],
)
```

Finally, declare an aspect for it, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:spotbugs.bzl", "lint_spotbugs_aspect")

spotbugs = lint_spotbugs_aspect(
    binary = Label("//tools/lint:spotbugs"),
    exclude_filter = Label("//:spotbugs-exclude.xml"),
)

```
"""

load("@rules_java//java:defs.bzl", "JavaInfo")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "noop_lint_action", "output_files", "should_visit")

_MNEMONIC = "AspectRulesLintSpotbugs"

def spotbugs_action(ctx, executable, srcs, target, exclude_filter, stdout, exit_code = None, args = []):
    """Run Spotbugs as an action under Bazel.

    Based on https://spotbugs.readthedocs.io/en/latest/index.html

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the Spotbugs program
        srcs: jar to be linted
        target: target to be linted
        exclude_filter: label of the spotbugs-exclude.xml file
        stdout: output file to generate
        exit_code: output file to write the exit code.
            If None, then fail the build when Spotbugs exits non-zero.
        args: additional command-line options, see https://spotbugs.readthedocs.io/en/latest/running.html#command-line-options
    """
    deps = target[JavaInfo].transitive_compile_time_jars
    outputs = [stdout]
    action_args = ctx.actions.args()
    action_args.add_all(args)

    # For java_binary targets, include their runtime dependencies
    all_runtime_jars = []
    if hasattr(ctx.rule.attr, "deps"):
        for dep in ctx.rule.attr.deps:
            if (JavaInfo in dep):
                all_runtime_jars += dep[JavaInfo].transitive_compile_time_jars.to_list()

    if exclude_filter:
        action_args.add_all(["-exclude", exclude_filter.path])

    src_args = ctx.actions.args()
    src_args.add_all(srcs)

    # Combine target's transitive runtime jars with dependency runtime jars
    all_classpath_jars = deps.to_list() + all_runtime_jars
    classpath_paths = [jar.path for jar in all_classpath_jars]
    if len(classpath_paths) > 0:
        action_args.add_all(["-auxclasspath", ":".join(classpath_paths)])

    action_args.add_all(["-exitcode"])

    if exit_code:
        command = "{SPOTBUGS} $@ >{stdout}; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        # Create empty stdout file on success, as Bazel expects one
        command = "{SPOTBUGS} $@ && touch {stdout}"

    # Include both the source jars and all runtime dependencies as inputs
    all_inputs = srcs + [exclude_filter] + all_runtime_jars
    ctx.actions.run_shell(
        inputs = depset(all_inputs, transitive = [deps]),
        outputs = outputs,
        command = command.format(SPOTBUGS = executable.path, stdout = stdout.path),
        arguments = [action_args, src_args],
        mnemonic = _MNEMONIC,
        tools = [executable],
        progress_message = "Linting %{label} with Spotbugs",
    )

# buildifier: disable=function-docstrings
def _spotbugs_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []
    srcs = ctx.rule.attr.srcs
    if len(srcs) == 0:
        return []
    files_to_lint = [jar.class_jar for jar in target[JavaInfo].outputs.jars]
    outputs, info = output_files(_MNEMONIC, target, ctx)
    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]
    format_options = []  # to define
    spotbugs_action(ctx, ctx.executable._spotbugs, files_to_lint, target, ctx.file._exclude_filter, outputs.human.out, outputs.human.exit_code, format_options + ctx.attr._args)
    spotbugs_action(ctx, ctx.executable._spotbugs, files_to_lint, target, ctx.file._exclude_filter, outputs.machine.out, outputs.machine.exit_code, format_options + ctx.attr._args)
    return [info]

def lint_spotbugs_aspect(binary, exclude_filter, rule_kinds = ["java_library", "java_binary", "java_test"], args = []):
    """A factory function to create a Spotbugs linter aspect.

    Args:
        binary: a Spotbugs executable
        exclude_filter: the Spotbugs exclude filter XML file
        rule_kinds: which target kinds should be visited by the aspect
        args: Additional options to pass to Spotbugs

    Returns:
        An aspect definition for Spotbugs
    """
    return aspect(
        implementation = _spotbugs_aspect_impl,
        # Edges we need to walk up the graph from the selected targets.
        # Needed for linters that need semantic information like transitive type declarations.
        # attr_aspects = ["deps"],
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_spotbugs": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_exclude_filter": attr.label(
                doc = "Report all bug instances except those matching the filter specified by this filter file",
                allow_single_file = True,
                default = exclude_filter,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
    )
