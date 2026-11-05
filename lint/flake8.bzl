"""API for declaring a flake8 lint aspect that visits py_library rules.

Typical usage:

First, fetch the flake8 package via your standard requirements file and python rules (pip, uv, etc).

Then, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")
py_console_script_binary(
    name = "flake8",
    pkg = "@pip//flake8:pkg",
)
```

Finally, create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:flake8.bzl", "lint_flake8_aspect")

flake8 = lint_flake8_aspect(
    binary = Label("//tools/lint:flake8"),
    config = Label("//:.flake8"),
)
```
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "should_visit")

_MNEMONIC = "AspectRulesLintFlake8"

def flake8_action(ctx, executable, srcs, config, stdout, exit_code = None, args = []):
    """Run flake8 as an action under Bazel.

    Based on https://flake8.pycqa.org/en/latest/user/invocation.html

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the flake8 program
        srcs: python files to be linted
        config: label of the flake8 config file (setup.cfg, tox.ini, or .flake8)
        stdout: output file containing stdout of flake8
        exit_code: output file containing exit code of flake8
            If None, then fail the build when flake8 exits non-zero.
        args: additional command-line options, see https://flake8.pycqa.org/en/latest/user/options.html
    """
    inputs = srcs + [config]
    outputs = [stdout]

    # Wire command-line options, see
    # https://flake8.pycqa.org/en/latest/user/options.html
    action_args = ctx.actions.args()
    action_args.add_all(args)
    action_args.add_all(srcs)
    action_args.add(config, format = "--config=%s")

    if exit_code:
        command = "{flake8} $@ >{stdout}; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        # Create empty stdout file on success, as Bazel expects one
        command = "{flake8} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        tools = [executable],
        command = command.format(flake8 = executable.path, stdout = stdout.path),
        arguments = [action_args],
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with Flake8",
    )

# buildifier: disable=function-docstring
def _flake8_aspect_impl(target, ctx):
    # Note: we don't inspect whether PyInfo in target to avoid a dep on rules_python
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    outputs, info = output_files(_MNEMONIC, target, ctx)

    files_to_lint = filter_srcs(ctx.rule)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    color_options = (["--color=always"] if ctx.attr._options[LintOptionsInfo].color else []) + ctx.attr._args
    flake8_action(ctx, ctx.executable._flake8, files_to_lint, ctx.file._config_file, outputs.human.out, outputs.human.exit_code, color_options)
    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    flake8_action(ctx, ctx.executable._flake8, files_to_lint, ctx.file._config_file, raw_machine_report, outputs.machine.exit_code, ctx.attr._args)
    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)
    return [info]

def lint_flake8_aspect(binary, config, rule_kinds = ["py_binary", "py_library"], args = []):
    """A factory function to create a linter aspect.

    Attrs:
        binary: a flake8 executable. Obtain from rules_python like so:

            load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")

            py_console_script_binary(
                name = "flake8",
                pkg = "@pip//flake8:pkg",
            )

        config: the flake8 config file (`setup.cfg`, `tox.ini`, or `.flake8`)
        args: additional command-line options to pass to flake8
    """
    return aspect(
        implementation = _flake8_aspect_impl,
        # Edges we need to walk up the graph from the selected targets.
        # Needed for linters that need semantic information like transitive type declarations.
        # attr_aspects = ["deps"],
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_flake8": attr.label(
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
