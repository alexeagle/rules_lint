"""API for declaring a Ruff lint aspect that visits py_{binary|library|test} rules.

Typical usage:

Ruff is provided as a built-in tool by rules_lint. To use the built-in version,
create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:ruff.bzl", "lint_ruff_aspect")

ruff = lint_ruff_aspect(
    binary = Label("@rules_lint//lint:ruff_bin",
    configs = [Label("//:.ruff.toml")],
)
```

## Using a specific ruff version

In `MODULE.bazel`, fetch the desired version from https://github.com/astral-sh/ruff/releases.

In `tools/lint/BUILD.bazel`, select the tool for the host platform:

```starlark
# Note: this won't interact properly with the --platform flag, see
# https://github.com/aspect-build/rules_lint/issues/389
alias(
    name = "ruff",
    actual = select({
        "@bazel_tools//src/conditions:linux_x86_64": "@ruff_x86_64-unknown-linux-gnu//:ruff",
        "@bazel_tools//src/conditions:linux_aarch64": "@ruff_aarch64-unknown-linux-gnu//:ruff",
        "@bazel_tools//src/conditions:darwin_arm64": "@ruff_aarch64-apple-darwin//:ruff",
        "@bazel_tools//src/conditions:darwin_x86_64": "@ruff_x86_64-apple-darwin//:ruff",
        "@bazel_tools//src/conditions:windows_x64": "@ruff_x86_64-pc-windows-msvc//:ruff.exe",
    }),
)
```

Finally, reference this tool alias rather than the one from `@multitool`:

```starlark
ruff = lint_ruff_aspect(
    binary = "@@//tools/lint:ruff",
    ...
)
```
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "patch_and_output_files", "should_visit")
load("//lint/private:patcher_action.bzl", "patcher_attrs", "run_patcher")

_MNEMONIC = "AspectRulesLintRuff"

def ruff_action(ctx, executable, srcs, config, stdout, exit_code = None, env = {}, patch = None, args = [], mnemonic = _MNEMONIC):
    """Run ruff as an action under Bazel.

    Ruff will select the configuration file to use for each source file, as documented here:
    https://docs.astral.sh/ruff/configuration/#config-file-discovery

    Note: all config files are passed to the action.
    This means that a change to any config file invalidates the action cache entries for ALL
    ruff actions.

    However, this is important because:

    1. ruff has an `extend` field, so it may need to read more than one config file
    2. ruff's logic for selecting the appropriate config needs to read the file content to detect a `[tool.ruff]` section.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the ruff program
        srcs: python files to be linted
        config: labels of ruff config files (pyproject.toml, ruff.toml, or .ruff.toml)
        stdout: output file of linter results to generate
        exit_code: output file to write the exit code.
            If None, then fail the build when ruff exits non-zero.
            See https://github.com/astral-sh/ruff/blob/dfe4291c0b7249ae892f5f1d513e6f1404436c13/docs/linter.md#exit-codes
        env: environment variaables for ruff
        patch: output file for patch (optional). If provided, uses run_patcher instead of run_shell.
        args: additional command-line arguments to pass to ruff
    """
    inputs = srcs + config

    action_args = ctx.actions.args()
    action_args.add("check")
    action_args.add("--force-exclude")
    action_args.add("--quiet")
    action_args.add_all(args)

    if patch != None:
        # Use run_patcher for fix mode
        action_args.add("--fix")
        action_args.add_all(srcs)

        run_patcher(
            ctx,
            ctx.executable,
            inputs = inputs,
            args = action_args,
            files_to_diff = [s.path for s in srcs],
            patch_cfg_env = env,
            patch_cfg_suffix = "{}patch_cfg".format(mnemonic + "." if mnemonic != _MNEMONIC else ""),
            patch_out = patch,
            tools = [executable],
            stdout = stdout,
            exit_code = exit_code,
            env = env,
            mnemonic = ctx.attr._mnemonic,
            progress_message = "Fixing %{label} with Ruff",
        )
    else:
        # Use run_shell for lint mode
        outputs = [stdout]
        action_args.add_all(srcs)
        if not env.get("FORCE_COLOR"):
            action_args.add("--output-format=concise")

        if exit_code:
            command = "{ruff} $@ >{stdout}; echo $? >" + exit_code.path
            outputs.append(exit_code)
        else:
            # Create empty file on success, as Bazel expects one
            command = "{ruff} $@ && touch {stdout}"

        ctx.actions.run_shell(
            inputs = inputs,
            outputs = outputs,
            command = command.format(ruff = executable.path, stdout = stdout.path),
            arguments = [action_args],
            mnemonic = ctx.attr._mnemonic,
            env = env,
            progress_message = "Linting %{label} with Ruff",
            tools = [executable],
        )

# buildifier: disable=function-docstring
def _ruff_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds, ctx.attr._filegroup_tags):
        return []

    files_to_lint = filter_srcs(ctx.rule)
    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(ctx.attr._mnemonic, target, ctx)
    else:
        outputs, info = output_files(ctx.attr._mnemonic, target, ctx)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    color_env = {"FORCE_COLOR": "1"} if ctx.attr._options[LintOptionsInfo].color else {}

    ruff_action(
        ctx,
        ctx.executable._ruff,
        files_to_lint,
        ctx.files._config_files,
        outputs.human.out,
        outputs.human.exit_code,
        env = color_env,
        patch = getattr(outputs, "patch", None),
        args = ctx.attr._args,
        mnemonic = ctx.attr._mnemonic,
    )

    # TODO(alex): if we run with --fix, this will report the issues that were fixed. Does a machine reader want to know about them?
    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = ctx.attr._mnemonic, suffix = "raw_machine_report"))
    ruff_action(ctx, ctx.executable._ruff, files_to_lint, ctx.files._config_files, raw_machine_report, outputs.machine.exit_code, args = ctx.attr._args)

    # Ideally we'd just use {"RUFF_OUTPUT_FORMAT": "sarif"} however it prints absolute paths; see https://github.com/astral-sh/ruff/issues/14985
    parse_to_sarif_action(ctx, ctx.attr._mnemonic, raw_machine_report, outputs.machine.out)

    return [info]

def lint_ruff_aspect(binary, configs, rule_kinds = ["py_binary", "py_library", "py_test"], filegroup_tags = ["python", "lint-with-ruff"], mnemonic = _MNEMONIC, args = []):
    """A factory function to create a linter aspect.

    Attrs:
        binary: a ruff executable
        configs: ruff config file(s) (`pyproject.toml`, `ruff.toml`, or `.ruff.toml`)
        rule_kinds: which [kinds](https://bazel.build/query/language#kind) of rules should be visited by the aspect
        filegroup_tags: filegroups tagged with these tags will be visited by the aspect in addition to Python rule kinds
        mnemonic: The mnemonic to use for the actions created by this aspect
        args: additional command-line arguments to pass to ruff
    """

    # syntax-sugar: allow a single config file in addition to a list
    if type(configs) == "string":
        configs = [configs]

    return aspect(
        implementation = _ruff_aspect_impl,
        attrs = patcher_attrs | {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_ruff": attr.label(
                default = binary,
                allow_files = True,
                executable = True,
                cfg = "exec",
            ),
            "_config_files": attr.label_list(
                default = configs,
                allow_files = True,
            ),
            "_filegroup_tags": attr.string_list(
                default = filegroup_tags,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
            "_mnemonic": attr.string(
                default = mnemonic,
                doc = "The mnemonic to use for the actions created by this aspect",
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
        toolchains = [OPTIONAL_SARIF_PARSER_TOOLCHAIN],
    )

def _ruff_workaround_20269_impl(rctx):
    # download_and_extract has a bug due to the use of Apache Commons library within Bazel,
    # See https://github.com/bazelbuild/bazel/issues/20269
    # To workaround, we fetch the file and then use the BSD tar on the system to extract it.
    rctx.download(sha256 = rctx.attr.sha256, url = rctx.attr.url, output = "ruff.tar.gz")
    tar_cmd = [rctx.which("tar"), "xzf", "ruff.tar.gz"]
    if rctx.attr.strip_prefix:
        tar_cmd.append("--strip-components=1")
    result = rctx.execute(tar_cmd)
    if result.return_code:
        fail("Couldn't extract ruff: \nSTDOUT:\n{}\nSTDERR:\n{}".format(result.out, result.stderr))
    rctx.file("BUILD", rctx.attr.build_file_content)

ruff_workaround_20269 = repository_rule(
    _ruff_workaround_20269_impl,
    doc = "Workaround for https://github.com/bazelbuild/bazel/issues/20269",
    attrs = {
        "build_file_content": attr.string(),
        "sha256": attr.string(),
        "strip_prefix": attr.string(doc = "unlike http_archive, any value causes us to pass --strip-components=1 to tar"),
        "url": attr.string(),
    },
)
