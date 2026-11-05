"""API for declaring a pydoclint lint aspect that visits Python rules.

Typical usage:

First, fetch the pydoclint package via your standard requirements file and
python rules (pip, uv, etc).

Then, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
load("@aspect_rules_py//py:defs.bzl", "py_binary")

py_binary(
    name = "pydoclint",
    srcs = ["pydoclint_wrapper.py"],
    main = "pydoclint_wrapper.py",
    deps = [
        "@pip//pydoclint",
    ],
)
```

Finally, create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:pydoclint.bzl", "lint_pydoclint_aspect")

pydoclint = lint_pydoclint_aspect(
    binary = Label("//tools/lint:pydoclint"),
    config = Label("//:pyproject.toml"),
)
```
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "should_visit")

_MNEMONIC = "AspectRulesLintPydoclint"

def pydoclint_action(ctx, executable, srcs, config, stdout, exit_code = None, env = {}, args = []):
    """Run pydoclint as an action under Bazel.

    Based on https://jsh9.github.io/pydoclint/

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the pydoclint program
        srcs: python files to be linted
        config: label of the pydoclint config file (`pyproject.toml` or another TOML file)
        stdout: output file containing stdout of pydoclint
        exit_code: output file containing exit code of pydoclint
            If None, then fail the build when pydoclint exits non-zero.
        env: environment variables for the pydoclint process
        args: additional command-line options
    """
    inputs = list(srcs)
    if config:
        inputs.append(config)
    outputs = [stdout]

    action_args = ctx.actions.args()
    action_args.add("--quiet")
    action_args.add("--show-filenames-in-every-violation-message=True")
    if config:
        action_args.add(config, format = "--config=%s")
    action_args.add_all(args)
    action_args.add_all(srcs)

    if exit_code:
        command = "{pydoclint} $@ >{stdout} 2>&1; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        command = "{pydoclint} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        tools = [executable],
        command = command.format(pydoclint = executable.path, stdout = stdout.path),
        arguments = [action_args],
        mnemonic = _MNEMONIC,
        env = env,
        progress_message = "Linting %{label} with pydoclint",
    )

# buildifier: disable=function-docstring
def _pydoclint_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds, ctx.attr._filegroup_tags):
        return []

    outputs, info = output_files(_MNEMONIC, target, ctx)
    files_to_lint = filter_srcs(ctx.rule)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    color_env = {"FORCE_COLOR": "1"} if ctx.attr._options[LintOptionsInfo].color else {}
    pydoclint_action(ctx, ctx.executable._pydoclint, files_to_lint, ctx.file._config_file, outputs.human.out, outputs.human.exit_code, env = color_env, args = ctx.attr._args)

    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    pydoclint_action(ctx, ctx.executable._pydoclint, files_to_lint, ctx.file._config_file, raw_machine_report, outputs.machine.exit_code, args = ctx.attr._args)

    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)
    return [info]

def lint_pydoclint_aspect(binary, config, rule_kinds = ["py_binary", "py_library", "py_test"], filegroup_tags = ["python", "lint-with-pydoclint"], args = []):
    """A factory function to create a linter aspect.

    Args:
        binary: a pydoclint executable. A small wrapper `py_binary` is recommended so
            human-readable output can call Click with `color=True`, for example:

            load("@aspect_rules_py//py:defs.bzl", "py_binary")

            py_binary(
                name = "pydoclint",
                srcs = ["pydoclint_wrapper.py"],
                main = "pydoclint_wrapper.py",
                deps = [
                    "@pip//pydoclint",
                ],
            )

        config: the pydoclint config file (`pyproject.toml` or another TOML file)
        rule_kinds: which [kinds](https://bazel.build/query/language#kind) of rules should be visited by the aspect
        filegroup_tags: filegroups tagged with these tags will also be visited by the aspect
        args: additional command-line options to pass to pydoclint
    """
    return aspect(
        implementation = _pydoclint_aspect_impl,
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_pydoclint": attr.label(
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
