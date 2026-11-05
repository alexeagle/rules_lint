"""Configures [taplo](https://taplo.tamasfe.dev/) to run as a Bazel aspect.

Typical usage:

Create an executable target for taplo, for example by aliasing the formatter binary
in `tools/lint/BUILD.bazel`:

```starlark
alias(
    name = "taplo",
    actual = "//tools/format:taplo",
)
```

Then declare the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:taplo.bzl", "lint_taplo_aspect")

taplo = lint_taplo_aspect(
    binary = Label("//tools/lint:taplo"),
    config = Label("//:.taplo.toml"),
)
```

Finally, opt TOML sources into linting by tagging a `filegroup` with `toml` or `lint-with-taplo`, or by
providing a custom `rule_kinds` list that matches your TOML rules.
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "should_visit")

_MNEMONIC = "AspectRulesLintTaplo"

def taplo_action(ctx, executable, srcs, stdout, exit_code = None, config = None, args = []):
    """Run Taplo lint as an action under Bazel.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: File representing the taplo program
        srcs: TOML files to lint
        stdout: output file for Taplo diagnostics
        exit_code: optional output file for exit code. If absent, non-zero exits fail the build.
        config: optional Taplo configuration file
        args: additional command-line options
    """
    inputs = list(srcs)
    if config:
        inputs.append(config)

    action_args = ctx.actions.args()
    action_args.add("lint")
    if config:
        action_args.add("--config")
        action_args.add(config.path)
    action_args.add_all(args)
    action_args.add_all(srcs)

    outputs = [stdout]
    if exit_code:
        # Taplo resolves file arguments to absolute paths under Bazel. When we capture its
        # output, strip the action working-directory prefix so reports use repo-relative paths.
        command = """set -euo pipefail
status=0
output=$("{taplo}" "$@" 2>&1) || status=$?
output=${{output//"$PWD/"/}}
printf '%s\n' "$output" > "{stdout}"
echo "$status" > """ + exit_code.path
        outputs.append(exit_code)
    else:
        # Create the output file on success, as Bazel expects one.
        command = "{taplo} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        arguments = [action_args],
        tools = [executable],
        command = command.format(
            taplo = executable.path,
            stdout = stdout.path,
        ),
        env = {"RUST_LOG": "off"},
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with Taplo",
    )

# buildifier: disable=function-docstring
def _taplo_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds, ctx.attr._filegroup_tags):
        return []

    files_to_lint = filter_srcs(ctx.rule)
    outputs, info = output_files(_MNEMONIC, target, ctx)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    color_options = ["--colors", "always"] if ctx.attr._options[LintOptionsInfo].color else ["--colors", "never"]
    common_options = ctx.attr._args

    taplo_action(
        ctx,
        ctx.executable._taplo,
        files_to_lint,
        outputs.human.out,
        outputs.human.exit_code,
        config = ctx.file._config_file,
        args = color_options + common_options,
    )

    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    taplo_action(
        ctx,
        ctx.executable._taplo,
        files_to_lint,
        raw_machine_report,
        outputs.machine.exit_code,
        config = ctx.file._config_file,
        args = ["--colors", "never"] + common_options,
    )

    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)
    return [info]

def lint_taplo_aspect(
        binary,
        config,
        rule_kinds = [],
        filegroup_tags = ["toml", "lint-with-taplo"],
        args = []):
    """Create a Taplo aspect.

    Args:
        binary: a taplo executable
        config: the label of the `.taplo.toml` or `taplo.toml` config file used by Taplo
        rule_kinds: which target kinds should be visited automatically
        filegroup_tags: which target tags opt a target into Taplo linting
        args: additional command-line arguments for `taplo lint`
    """
    return aspect(
        implementation = _taplo_aspect_impl,
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_taplo": attr.label(
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
        toolchains = [OPTIONAL_SARIF_PARSER_TOOLCHAIN],
    )
