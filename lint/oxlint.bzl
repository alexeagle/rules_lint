"""Configures [Oxlint](https://oxc.rs/docs/guide/usage/linter.html) to run as a Bazel aspect.

First, add `oxlint` to your npm dependencies and declare its binary, typically in
`tools/lint/BUILD.bazel`:

```starlark
load("@npm//:oxlint/package_json.bzl", oxlint_bin = "bin")

oxlint_bin.oxlint_binary(name = "oxlint")
```

Then declare the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:oxlint.bzl", "lint_oxlint_aspect")

oxlint = lint_oxlint_aspect(
    binary = Label("//tools/lint:oxlint"),
    config = Label("//:.oxlintrc.json"),
)
```
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "patch_and_output_files", "should_visit")
load("//lint/private:patcher_action.bzl", "patcher_attrs", "run_patcher")

_MNEMONIC = "AspectRulesLintOxlint"

def oxlint_action(ctx, executable, srcs, config, stdout, exit_code = None, args = [], format = None, patch = None):
    """Run Oxlint as a Bazel action.

    Args:
        ctx: Bazel rule or aspect evaluation context
        executable: the Oxlint executable
        srcs: JavaScript or TypeScript files to lint
        config: Oxlint JSON or JSONC configuration file
        stdout: output file for diagnostics
        exit_code: optional output file for the exit code; without it, violations fail the action
        args: additional Oxlint command-line arguments
        format: optional Oxlint output format
        patch: optional output patch; when present, run Oxlint with `--fix`
    """
    action_args = ctx.actions.args()
    action_args.add_all(args)
    action_args.add_all(["--config", config.path])
    if format:
        action_args.add_all(["--format", format])
    if patch:
        action_args.add("--fix")
    action_args.add_all(srcs)

    inputs = srcs + [config]
    if patch:
        run_patcher(
            ctx,
            ctx.executable,
            inputs = inputs,
            args = action_args,
            files_to_diff = [src.path for src in srcs],
            patch_out = patch,
            patch_cfg_env = {"BAZEL_BINDIR": "."},
            tools = [executable],
            exit_code = exit_code,
            mnemonic = _MNEMONIC,
            progress_message = "Fixing %{label} with Oxlint",
        )
        return

    outputs = [stdout]
    if exit_code:
        command = "{oxlint} $@ >{stdout} 2>&1; echo $? >{exit_code}"
        outputs.append(exit_code)
    else:
        command = "{oxlint} $@ >{stdout} 2>&1"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        arguments = [action_args],
        command = command.format(
            oxlint = executable.path,
            stdout = stdout.path,
            exit_code = exit_code.path if exit_code else "",
        ),
        env = {"BAZEL_BINDIR": "."},
        tools = [executable],
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with Oxlint",
    )

# buildifier: disable=function-docstring
def _oxlint_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds, ctx.attr._filegroup_tags):
        return []

    files_to_lint = filter_srcs(ctx.rule)
    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(_MNEMONIC, target, ctx)
    else:
        outputs, info = output_files(_MNEMONIC, target, ctx)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    # Always report the original violations. Fixes are produced by a separate action so
    # `aspect lint` still exits non-zero when it offers an unapplied patch.
    oxlint_action(
        ctx,
        ctx.executable._oxlint,
        files_to_lint,
        ctx.file._config_file,
        outputs.human.out,
        outputs.human.exit_code,
        args = ctx.attr._args,
    )

    if ctx.attr._options[LintOptionsInfo].fix:
        patch_exit_code = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "patch.exit_code"))
        oxlint_action(
            ctx,
            ctx.executable._oxlint,
            files_to_lint,
            ctx.file._config_file,
            None,
            patch_exit_code,
            args = ctx.attr._args,
            patch = outputs.patch,
        )

    # Oxlint emits SARIF natively, so no rules_lint parser action is needed.
    oxlint_action(
        ctx,
        ctx.executable._oxlint,
        files_to_lint,
        ctx.file._config_file,
        outputs.machine.out,
        outputs.machine.exit_code,
        args = ctx.attr._args,
        format = "sarif",
    )

    return [info]

def lint_oxlint_aspect(
        binary,
        config,
        rule_kinds = ["js_library", "ts_project", "ts_project_rule"],
        filegroup_tags = ["lint-with-oxlint"],
        args = []):
    """Create an Oxlint aspect.

    Args:
        binary: an Oxlint executable
        config: an Oxlint JSON or JSONC configuration file
        rule_kinds: target kinds visited automatically
        filegroup_tags: tags that opt filegroups into Oxlint
        args: additional Oxlint command-line arguments
    """
    return aspect(
        implementation = _oxlint_aspect_impl,
        attrs = patcher_attrs | {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_oxlint": attr.label(
                default = binary,
                allow_files = True,
                executable = True,
                cfg = "exec",
            ),
            "_config_file": attr.label(
                default = config,
                allow_single_file = True,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
            "_filegroup_tags": attr.string_list(
                default = filegroup_tags,
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
    )
