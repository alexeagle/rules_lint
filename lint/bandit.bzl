"""API for declaring a bandit lint aspect that visits supported rules.

Typical usage:

First, fetch `bandit[sarif]` package via your standard requirements file and python rules (pip, uv, etc).

Note that the `sarif` extra is **required** for machine output and the `toml` extra
is recommended to enable `pyproject.toml` support, see examples.

Then, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")

py_console_script_binary(
    name = "bandit",
    script = "bandit",
    pkg = "@pip//bandit:pkg",
)
```

Finally, create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:bandit.bzl", "lint_bandit_aspect")

bandit = lint_bandit_aspect(
    binary = Label("//tools/lint:bandit"),  # requires [sarif] extra
    config = Label("//:pyproject.toml"),  # requires [toml] extra
)
```
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "filter_srcs", "noop_lint_action", "output_files", "should_visit")

_MNEMONIC = "AspectRulesLintBandit"

def bandit_action(
        ctx,
        executable,
        srcs,
        config,
        stdout,
        exit_code = None,
        env = {},
        args = []):
    """Run bandit as an action under Bazel.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the bandit program
        srcs: files to be linted
        config: label of the directory with bandit rules (defaults to `auto`).
        stdout: output file containing stdout of bandit
        exit_code: output file containing exit code of bandit
            If None, then fail the build when bandit exits non-zero.
        env: environment variables passed to the tool.
        args: additional command-line options
    """
    inputs = []
    inputs.extend(srcs)
    outputs = [stdout]

    if len(config) > 1:
        fail("Requires a single config argument")

    action_args = ctx.actions.args()
    action_args.add("--quiet")
    action_args.add_all(ctx.attr._args)
    if config:
        action_args.add(config[0], format = "--config=%s")
        inputs.append(config[0])
    action_args.add_all(args)
    action_args.add("--")
    action_args.add_all(srcs)

    if exit_code:
        command = "{bandit} $@ > {stdout}; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        command = "{bandit} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        tools = [executable._bandit],
        command = command.format(bandit = executable._bandit.path, stdout = stdout.path),
        arguments = [action_args],
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with bandit",
        env = env,
    )

# buildifier: disable=function-docstring
def _bandit_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    outputs, info = output_files(_MNEMONIC, target, ctx)
    files_to_lint = filter_srcs(ctx.rule)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    bandit_action(
        ctx,
        ctx.executable,
        files_to_lint,
        ctx.files._config,
        outputs.human.out,
        outputs.human.exit_code,
        env = ctx.attr._env,
        args = [],
    )
    bandit_action(
        ctx,
        ctx.executable,
        files_to_lint,
        ctx.files._config,
        outputs.machine.out,
        outputs.machine.exit_code,
        env = ctx.attr._env,
        args = ["--format=sarif"],
    )
    return [info]

RULE_KINDS = ["py_binary", "py_library", "py_test"]

def lint_bandit_aspect(
        binary,
        config,
        args = [],
        env = {},
        rule_kinds = RULE_KINDS):
    """A factory function to create a linter aspect.

    Args:
        binary: a bandit executable. Obtain from pypi like so:

            load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")

            py_console_script_binary(
                name = "bandit",
                script = "bandit",
                pkg = "@pip//bandit:pkg",
            )

        config: label of the directory with bandit rules (defaults to `auto`).
        args: extra options passed to bandit (["--severity-level=medium"] for example).
        env: environment variables passed to the tool.
        rule_kinds: which [kinds](https://bazel.build/query/language#kind) of rules should be visited by the aspect
    """
    return aspect(
        implementation = _bandit_aspect_impl,
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_bandit": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_config": attr.label(
                default = config,
                allow_single_file = True,
            ),
            "_args": attr.string_list(
                default = args,
            ),
            "_env": attr.string_dict(
                default = env,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
        },
    )
