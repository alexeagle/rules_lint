"""API for declaring a PMD lint aspect that visits java_library rules.

Typical usage:

```
load("@aspect_rules_lint//lint:pmd.bzl", "pmd_aspect")

pmd = pmd_aspect(
    binary = "@@//:PMD",
    # config = "@@//:.PMD",
)
```
"""

def pmd_action(ctx, executable, srcs, rulesets, report, use_exit_code = False):
    """Run PMD as an action under Bazel.

    Based on https://docs.pmd-code.org/latest/pmd_userdocs_installation.html#running-pmd-via-command-line

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the the PMD program
        srcs: java files to be linted
        rulesets: list of labels of the PMD ruleset files
        report: output file to generate
        use_exit_code: whether to fail the build when a lint violation is reported
    """
    inputs = srcs + rulesets
    outputs = [report]

    # Wire command-line options, see
    # https://docs.pmd-code.org/latest/pmd_userdocs_cli_reference.html
    args = ctx.actions.args()
    args.add_all(["--report-file", report])
    args.add("--rulesets")
    args.add_joined(rulesets, join_with = ",")
    if not use_exit_code:
        # NB: this arg changes in PMD 7
        args.add_all(["--fail-on-violation", "false"])

    src_args = ctx.actions.args()
    src_args.use_param_file("%s", use_always = True)
    src_args.add_all(srcs)

    ctx.actions.run(
        inputs = inputs,
        outputs = outputs,
        executable = executable,
        arguments = [args, "--file-list", src_args],
        mnemonic = "PMD",
    )

# buildifier: disable=function-docstring
def _pmd_aspect_impl(target, ctx):
    if ctx.rule.kind in ["java_library"]:
        report = ctx.actions.declare_file(target.label.name + ".PMD-report.txt")
        pmd_action(ctx, ctx.executable._pmd, ctx.rule.files.srcs, ctx.files._rulesets, report, ctx.attr.fail_on_violation)
        results = depset([report])
    else:
        results = depset()

    return [
        OutputGroupInfo(rules_lint_report = results),
    ]

def pmd_aspect(binary, rulesets):
    """A factory function to create a linter aspect.

    Attrs:
        binary: a PMD executable. Can be obtained from rules_java like so:

            ```
            java_binary(
                name = "pmd",
                main_class = "net.sourceforge.pmd.PMD",
                # Point to wherever you have the java_import rule defined, see our example
                runtime_deps = ["@net_sourceforge_pmd"],
            )
            ```

        rulesets: the PMD ruleset XML files
    """
    return aspect(
        implementation = _pmd_aspect_impl,
        # Edges we need to walk up the graph from the selected targets.
        # Needed for linters that need semantic information like transitive type declarations.
        # attr_aspects = ["deps"],
        attrs = {
            "fail_on_violation": attr.bool(),
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
        },
    )
