"""API for declaring a shellcheck lint aspect that visits sh_{binary|library|test} rules.

Typical usage:

Shellcheck is provided as a built-in tool by rules_lint. To use the built-in version,
create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:shellcheck.bzl", "lint_shellcheck_aspect")

shellcheck = lint_shellcheck_aspect(
    binary = Label("@rules_lint//lint:shellcheck_bin",
    config = Label("//:.shellcheckrc"),
)
```
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "patch_and_output_files", "should_visit")

_MNEMONIC = "AspectRulesLintShellCheck"

def shellcheck_action(ctx, executable, srcs, transitive_srcs, config, stdout, exit_code = None, args = []):
    """Run shellcheck as an action under Bazel.

    Based on https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the shellcheck program
        srcs: bash files to be linted
        transitive_srcs: depset of sourced shell files required for source resolution
        config: label of the .shellcheckrc file
        stdout: output file containing stdout of shellcheck
        exit_code: output file containing shellcheck exit code.
            If None, then fail the build when vale exits non-zero.
            See https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md#return-values
        args: additional command-line options, see https://github.com/koalaman/shellcheck/blob/master/shellcheck.hs#L95
    """
    inputs = depset(srcs + [config], transitive = [transitive_srcs])

    # Wire command-line options, see
    # https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md#options
    action_args = ctx.actions.args()
    action_args.add_all(args)
    action_args.add_all(srcs)
    outputs = [stdout]

    if exit_code:
        command = "{shellcheck} $@ >{stdout}; echo $? >" + exit_code.path
        outputs.append(exit_code)
    else:
        # Create empty file on success, as Bazel expects one
        command = "{shellcheck} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        command = command.format(
            shellcheck = executable.path,
            stdout = stdout.path,
        ),
        arguments = [action_args],
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with ShellCheck",
        tools = [executable],
    )

# buildifier: disable=function-docstring
def _shellcheck_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    transitive_sources = []
    if hasattr(ctx.rule.attr, "deps"):
        # rules_shell exposes sh_library sources through target.files.
        # Provide those files as action inputs so ShellCheck can resolve `source`
        # statements without linting deps as separate command-line arguments.
        for dep in ctx.rule.attr.deps:
            transitive_sources.append(dep.files)
    transitive_srcs = depset(transitive = transitive_sources)

    files_to_lint = filter_srcs(ctx.rule)
    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(_MNEMONIC, target, ctx)
    else:
        outputs, info = output_files(_MNEMONIC, target, ctx)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    color_options = ["--color"] if ctx.attr._options[LintOptionsInfo].color else []
    config_options = ["--rcfile", ctx.file._config_file]

    # shellcheck does not have a --fix mode that applies fixes for some violations while reporting others.
    # So we must run an action to generate the report separately from an action that writes the human-readable report.
    if hasattr(outputs, "patch"):
        discard_exit_code = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "patch_exit_code"))
        shellcheck_action(ctx, ctx.executable._shellcheck, files_to_lint, transitive_srcs, ctx.file._config_file, outputs.patch, discard_exit_code, ["--format", "diff"] + ctx.attr._args)

    shellcheck_action(ctx, ctx.executable._shellcheck, files_to_lint, transitive_srcs, ctx.file._config_file, outputs.human.out, outputs.human.exit_code, color_options + config_options + ctx.attr._args)
    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    shellcheck_action(ctx, ctx.executable._shellcheck, files_to_lint, transitive_srcs, ctx.file._config_file, raw_machine_report, outputs.machine.exit_code, config_options + ctx.attr._args)

    # Shellcheck does not have a SARIF output format built-in.
    # We could use https://crates.io/crates/shellcheck-sarif but don't want to introduce a Rust dependency.
    # So we use our Go tool sarif.go to translate the raw machine-readable report to SARIF.
    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)

    return [info]

def lint_shellcheck_aspect(binary, config, rule_kinds = ["sh_binary", "sh_library", "sh_test"], args = []):
    """A factory function to create a linter aspect.

    Attrs:
        binary: a shellcheck executable.
        config: the .shellcheckrc file
        args: Additional options to pass to ShellCheck
    """
    return aspect(
        implementation = _shellcheck_aspect_impl,
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_shellcheck": attr.label(
                default = binary,
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
            "_args": attr.string_list(
                default = args,
            ),
        },
        toolchains = [OPTIONAL_SARIF_PARSER_TOOLCHAIN],
    )
