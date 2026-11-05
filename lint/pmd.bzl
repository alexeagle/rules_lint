"""API for declaring a PMD lint aspect that visits java_library rules.

Typical usage:

First, call the tools.pmd module extension to download the zip file.
Alternatively you could use whatever you prefer for managing Java dependencies, such as a Maven integration rule.

Next, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
java_binary(
    name = "pmd",
    main_class = "net.sourceforge.pmd.PMD",
    runtime_deps = ["@net_sourceforge_pmd"],
)
```

Finally, declare an aspect for it, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:pmd.bzl", "lint_pmd_aspect")

pmd = lint_pmd_aspect(
    binary = Label("//tools/lint:pmd"),
    rulesets = [Label("//:pmd.xml")],
)
```
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "should_visit")

_MNEMONIC = "AspectRulesLintPMD"

def pmd_action(ctx, executable, srcs, rulesets, stdout, exit_code = None, args = []):
    """Run PMD as an action under Bazel.

    Based on https://docs.pmd-code.org/latest/pmd_userdocs_installation.html#running-pmd-via-command-line

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the PMD program
        srcs: java files to be linted
        rulesets: list of labels of the PMD ruleset files
        stdout: output file to generate
        exit_code: output file to write the exit code.
            If None, then fail the build when PMD exits non-zero.
        args: additional command-line options, see https://pmd.github.io/pmd/pmd_userdocs_cli_reference.html
    """
    inputs = srcs + rulesets
    outputs = [stdout]

    # Wire command-line options, see
    # https://docs.pmd-code.org/latest/pmd_userdocs_cli_reference.html
    action_args = ctx.actions.args()
    action_args.add("check")
    action_args.add("--no-progress")

    # https://docs.pmd-code.org/pmd-doc-7.7.0/pmd_userdocs_incremental_analysis.html
    # is non-hermetic, and requires some thought and care before trying to use previous results.
    # If this is actually needed, it will probably have to be run as a Persistent worker :(
    action_args.add("--no-cache")
    action_args.add_all(args)
    action_args.add("--rulesets")
    action_args.add_joined(rulesets, join_with = ",")

    src_args = ctx.actions.args()
    src_args.use_param_file("%s", use_always = True)
    src_args.add_all(srcs)

    if exit_code:
        action_args.add_all(["--report-file", stdout.path])
        command = "{PMD} $@; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        # Create empty stdout file on success, as Bazel expects one
        command = "{PMD} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        command = command.format(PMD = executable.path, stdout = stdout.path),
        arguments = [action_args, "--file-list", src_args],
        mnemonic = _MNEMONIC,
        tools = [executable],
        progress_message = "Linting %{label} with PMD",
    )

# buildifier: disable=function-docstring
def _pmd_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    files_to_lint = filter_srcs(ctx.rule)
    outputs, info = output_files(_MNEMONIC, target, ctx)
    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    # https://github.com/pmd/pmd/blob/master/docs/pages/pmd/userdocs/pmd_report_formats.md
    format_options = ["--format", "textcolor" if ctx.attr._options[LintOptionsInfo].color else "text"]
    pmd_action(ctx, ctx.executable._pmd, files_to_lint, ctx.files._rulesets, outputs.human.out, outputs.human.exit_code, format_options + ctx.attr._args)
    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    pmd_action(ctx, ctx.executable._pmd, files_to_lint, ctx.files._rulesets, raw_machine_report, outputs.machine.exit_code, ctx.attr._args)
    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)
    return [info]

def lint_pmd_aspect(binary, rulesets, rule_kinds = ["java_binary", "java_library"], args = []):
    """A factory function to create a linter aspect.

    Attrs:
        binary: a PMD executable. Obtain from rules_java like so:

            java_binary(
                name = "pmd",
                main_class = "net.sourceforge.pmd.PMD",
                # Point to wherever you have the java_import rule defined, see our example
                runtime_deps = ["@net_sourceforge_pmd"],
            )

        rulesets: the PMD ruleset XML files
        args: Additional options to pass to PMD
    """
    return aspect(
        implementation = _pmd_aspect_impl,
        # Edges we need to walk up the graph from the selected targets.
        # Needed for linters that need semantic information like transitive type declarations.
        # attr_aspects = ["deps"],
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_pmd": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_rulesets": attr.label_list(
                allow_files = True,
                mandatory = True,
                allow_empty = False,
                doc = "Ruleset files.",
                default = rulesets,
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
