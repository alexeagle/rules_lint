"""API for declaring a pylint lint aspect that visits Python rules.

Typical usage:

First, fetch the pylint package via your standard requirements file and python rules (pip, uv, etc).

Then, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")

py_console_script_binary(
    name = "pylint",
    pkg = "@pip//pylint:pkg",
)
```

Finally, create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:pylint.bzl", "lint_pylint_aspect")

pylint = lint_pylint_aspect(
    binary = Label("//tools/lint:pylint"),
    config = Label("//:.pylintrc"),
)
```
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "should_visit")

_MNEMONIC = "AspectRulesLintPylint"
_BASE_OPTIONS = [
    "--reports=n",
    "--score=n",
    "--persistent=n",
]

def pylint_action(ctx, executable, srcs, config, stdout, exit_code = None, args = []):
    """Run pylint as an action under Bazel.

    Based on https://pylint.readthedocs.io/en/stable/user_guide/run.html

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the pylint program
        srcs: python files to be linted
        config: label of the pylint config file (pyproject.toml, .pylintrc, or setup.cfg)
        stdout: output file containing stdout of pylint
        exit_code: output file containing exit code of pylint
            If None, then fail the build when pylint exits non-zero.
        args: additional command-line options
    """
    inputs = list(srcs)
    if config:
        inputs.append(config)
    outputs = [stdout]

    action_args = ctx.actions.args()
    action_args.add_all(_BASE_OPTIONS)
    if config:
        action_args.add(config, format = "--rcfile=%s")
    action_args.add_all(args)
    action_args.add_all(srcs)

    if exit_code:
        command = "{pylint} $@ >{stdout}; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        command = "{pylint} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        tools = [executable],
        command = command.format(pylint = executable.path, stdout = stdout.path),
        arguments = [action_args],
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with Pylint",
    )

# buildifier: disable=function-docstring
def _pylint_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds, ctx.attr._filegroup_tags):
        return []

    outputs, info = output_files(_MNEMONIC, target, ctx)
    files_to_lint = filter_srcs(ctx.rule)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    human_options = ctx.attr._args + (["--output-format=colorized"] if ctx.attr._options[LintOptionsInfo].color else ["--output-format=text"])
    pylint_action(ctx, ctx.executable._pylint, files_to_lint, ctx.file._config_file, outputs.human.out, outputs.human.exit_code, args = human_options)

    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    pylint_action(ctx, ctx.executable._pylint, files_to_lint, ctx.file._config_file, raw_machine_report, outputs.machine.exit_code, args = ctx.attr._args + ["--output-format=text"])

    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)
    return [info]

def lint_pylint_aspect(binary, config, rule_kinds = ["py_binary", "py_library", "py_test"], filegroup_tags = ["python", "lint-with-pylint"], args = []):
    """A factory function to create a linter aspect.

    Args:
        binary: a pylint executable. Obtain from rules_python like so:

            load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")

            py_console_script_binary(
                name = "pylint",
                pkg = "@pip//pylint:pkg",
            )

        config: the pylint config file (`pyproject.toml`, `pylintrc`, or `.pylintrc`)
        rule_kinds: which [kinds](https://bazel.build/query/language#kind) of rules should be visited by the aspect
        filegroup_tags: filegroups tagged with these tags will also be visited by the aspect
        args: additional command-line options to pass to pylint
    """
    return aspect(
        implementation = _pylint_aspect_impl,
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_pylint": attr.label(
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
            "_filegroup_tags": attr.string_list(
                default = filegroup_tags,
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
        toolchains = [OPTIONAL_SARIF_PARSER_TOOLCHAIN],
    )
