"Helpers to reduce boilerplate for writing linter aspects"

LintOptionsInfo = provider(
    doc = "Global options for running linters",
    fields = {
        "color": "whether ANSI color escape codes are desired in the human-readable stdout",
        "debug": "print additional information for rules_lint developers",
        "fail_on_violation": "whether to honor the exit code of linter tools run as actions",
        "fix": "whether to run linters in their --fix mode. Fixes are collected into patch files.",
    },
)

def _lint_options_impl(ctx):
    return LintOptionsInfo(
        color = ctx.attr.color,
        debug = ctx.attr.debug,
        fail_on_violation = ctx.attr.fail_on_violation,
        fix = ctx.attr.fix,
    )

lint_options = rule(
    implementation = _lint_options_impl,
    attrs = {
        "color": attr.bool(),
        "debug": attr.bool(),
        "fix": attr.bool(),
        "fail_on_violation": attr.bool(),
    },
)

def should_visit(rule, allow_kinds, allow_filegroup_tags = []):
    """Determine whether a rule is meant to be visited by a linter aspect

    A target with the "no-lint" tag will not be visited.

    Args:
        rule: a [rules_attributes](https://bazel.build/rules/lib/builtins/rule_attributes.html) object
        allow_kinds (list of string): return true if the rule's kind is in the list, a value of ["*"] returns true for all rule kinds
        allow_filegroup_tags (list of string): return true if the rule is a filegroup and has a tag in this list

    Returns:
        whether to apply the aspect on this rule
    """
    if "no-lint" in rule.attr.tags:
        return False

    if rule.kind in allow_kinds or allow_kinds == ["*"]:
        return True
    if rule.kind == "filegroup":
        for allow_tag in allow_filegroup_tags:
            if allow_tag in rule.attr.tags:
                return True
    return False

OUTFILE_FORMAT = "{label}.{mnemonic}.{suffix}"

def output_files(mnemonic, target, ctx, sibling = None, files_to_lint = None):
    """Declare linter output files.

    Args:
        mnemonic: used as part of the filename
        target: the target being visited by a linter aspect
        ctx: the aspect context
        sibling: optional File to declare outputs as siblings of, placing them in
            the same directory as the sibling file.
        files_to_lint: optional list of files, if provided one output will be created per file

    Returns:
        tuple of struct() of output files, and the OutputGroupInfo provider that the rule should return when files_to_lint is None
        tuple of list of struct() of output files, and the OutputGroupInfo provider when files_to_lint is provided
    """
    human_outputs = []
    machine_outputs = []

    def _declare_outputs(suffix = ""):
        """Helper function to declare the outputs"""
        human_out = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name + suffix, mnemonic = mnemonic, suffix = "out"), sibling = sibling)

        # NB: named ".report" as there are existing callers depending on that
        machine_out = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name + suffix, mnemonic = mnemonic, suffix = "report"), sibling = sibling)

        if ctx.attr._options[LintOptionsInfo].fail_on_violation:
            # Fail on violation means the exit code is reported to Bazel as the action result
            human_exit_code = None
            machine_exit_code = None
        else:
            # The exit codes should instead be provided as action outputs so the build succeeds.
            # Downstream tooling like `aspect lint` will be responsible for reading the exit codes
            # and interpreting them.
            human_exit_code = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name + suffix, mnemonic = mnemonic, suffix = "out.exit_code"), sibling = sibling)
            machine_exit_code = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name + suffix, mnemonic = mnemonic, suffix = "report.exit_code"), sibling = sibling)

        human_outputs = [f for f in [human_out, human_exit_code] if f]
        machine_outputs = [f for f in [machine_out, machine_exit_code] if f]
        return struct(
            human = struct(
                out = human_out,
                exit_code = human_exit_code,
            ),
            machine = struct(
                out = machine_out,
                exit_code = machine_exit_code,
            ),
        ), human_outputs, machine_outputs

    if files_to_lint == None:
        s, human_outputs, machine_outputs = _declare_outputs()
        return s, OutputGroupInfo(
            rules_lint_human = depset(human_outputs),
            rules_lint_machine = depset(machine_outputs),
            # Always cause the action to execute, even if the output isn't requested
            _validation = depset(human_outputs[0:1]),
        )

    s_out = []
    validation_set = []
    for f in files_to_lint:
        f_s, f_human_outputs, f_machine_outputs = _declare_outputs("_rules_lint/" + f.short_path)
        s_out.append(f_s)
        human_outputs += f_human_outputs
        machine_outputs += f_machine_outputs
        validation_set.append(f_human_outputs[0])

    return s_out, OutputGroupInfo(
        rules_lint_human = depset(human_outputs),
        rules_lint_machine = depset(machine_outputs),
        # Always cause the action to execute, even if the output isn't requested
        _validation = depset(validation_set),
    )

def patch_file(mnemonic, target, ctx, sibling = None, files_to_lint = None):
    if files_to_lint == None:
        patch = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = mnemonic, suffix = "patch"), sibling = sibling)
        return patch, OutputGroupInfo(rules_lint_patch = depset([patch]))
    patches = []
    for f in files_to_lint:
        patches.append(ctx.actions.declare_file(OUTFILE_FORMAT.format(
            label = target.label.name + "_rules_lint/" + f.short_path,
            mnemonic = mnemonic,
            suffix = "patch",
        ), sibling = sibling))
    return patches, OutputGroupInfo(rules_lint_patch = depset(patches))

# If we return multiple OutputGroupInfo from a rule implementation, only one will get used.
# So we need a separate function to return both.
# buildifier: disable=function-docstring
def patch_and_output_files(mnemonic, target, ctx, sibling = None, files_to_lint = None):
    patch, _ = patch_file(mnemonic, target, ctx, sibling = sibling, files_to_lint = files_to_lint)
    outputs, _ = output_files(mnemonic, target, ctx, sibling = sibling, files_to_lint = files_to_lint)
    if files_to_lint == None:
        human_outputs = [f for f in [outputs.human.out, outputs.human.exit_code] if f]
        machine_outputs = [f for f in [outputs.machine.out, outputs.machine.exit_code] if f]
        return struct(
            human = outputs.human,
            machine = outputs.machine,
            patch = patch,
        ), OutputGroupInfo(
            rules_lint_human = depset(human_outputs),
            rules_lint_machine = depset(machine_outputs),
            rules_lint_patch = depset([patch]),
        )
    human_outputs = [f for o in outputs for f in [o.human.out, o.human.exit_code] if f]
    machine_outputs = [f for o in outputs for f in [o.machine.out, o.machine.exit_code] if f]
    return [
        struct(
            human = o.human,
            machine = o.machine,
            patch = p,
        )
        for o, p in zip(outputs, patch)
    ], OutputGroupInfo(
            rules_lint_human = depset(human_outputs),
            rules_lint_machine = depset(machine_outputs),
            rules_lint_patch = depset(patch),
        )

def filter_srcs(rule):
    if "lint-genfiles" in rule.attr.tags:
        return rule.files.srcs
    else:
        return [s for s in rule.files.srcs if s.is_source and s.owner.workspace_name == ""]

def noop_lint_action(ctx, outputs):
    """Action that creates expected outputs when no files are provided to a lint action.

    This is needed for a linter that does the wrong thing when given zero srcs to inspect,
    for example it might error, or try to lint all files it can find.
    It is also a performance optimisation in other cases; use this in every linter implementation.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        outputs: struct returned from output_files or patch_and_output_files
    """
    commands = []
    commands.append("touch {}".format(outputs.human.out.path))
    commands.append("touch {}".format(outputs.machine.out.path))

    outs = [outputs.human.out, outputs.machine.out]

    # NB: if we write JSON machine-readable outputs, then an empty file won't be appropriate
    if outputs.human.exit_code:
        commands.append("echo 0 > {}".format(outputs.human.exit_code.path))
        outs.append(outputs.human.exit_code)

    if outputs.machine.exit_code:
        commands.append("echo 0 > {}".format(outputs.machine.exit_code.path))
        outs.append(outputs.machine.exit_code)

    if hasattr(outputs, "patch"):
        commands.append("touch {}".format(outputs.patch.path))
        outs.append(outputs.patch)

    ctx.actions.run_shell(
        inputs = [],
        outputs = outs,
        command = " && ".join(commands),
    )

SARIF_PARSER_TOOLCHAIN = Label("@rules_lint//tools/toolchains:sarif_parser_toolchain_type")
OPTIONAL_SARIF_PARSER_TOOLCHAIN = config_common.toolchain_type(SARIF_PARSER_TOOLCHAIN, mandatory = False)

def parse_to_sarif_action(ctx, mnemonic, raw_machine_report, sarif_out):
    """Translate a machine-readable report to SARIF format by running our Go tool sarif.go.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        mnemonic: the mnemonic identifier for the linter being used
        raw_machine_report: the raw machine-readable report
        sarif_out: the SARIF output file
    """
    sarif_parser_toolchain = ctx.toolchains[SARIF_PARSER_TOOLCHAIN]
    if not sarif_parser_toolchain:
        ctx.actions.symlink(output = sarif_out, target_file = raw_machine_report)
        return

    args = ctx.actions.args()
    args.add("-in", raw_machine_report.path)
    args.add("-out", sarif_out.path)
    args.add("-label", ctx.label)
    args.add("-mnemonic", mnemonic)

    ctx.actions.run(
        inputs = [raw_machine_report],
        outputs = [sarif_out],
        arguments = [args],
        mnemonic = "AspectRulesLintParseToSarif",
        progress_message = "Parsing machine-readable report to SARIF for %{label}",
        executable = sarif_parser_toolchain.sarif_parser_info.bin,
        toolchain = SARIF_PARSER_TOOLCHAIN,
    )
