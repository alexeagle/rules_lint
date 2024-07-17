"Helpers to reduce boilerplate for writing linter aspects"

LintOptionsInfo = provider(
    doc = "Global options for running linters",
    fields = {
        "debug": "print additional information for rules_lint developers",
        "fail_on_violation": "whether to honor the exit code of linter tools run as actions",
        "fix": "whether to run linters in their --fix mode. Fixes are collected into patch files.",
    },
)

def _lint_options_impl(ctx):
    return LintOptionsInfo(
        debug = ctx.attr.debug,
        fail_on_violation = ctx.attr.fail_on_violation,
        fix = ctx.attr.fix,
    )

lint_options = rule(
    implementation = _lint_options_impl,
    attrs = {
        "debug": attr.bool(),
        "fix": attr.bool(),
        "fail_on_violation": attr.bool(),
    },
)

def should_visit(rule, allow_kinds, allow_filegroup_tags = []):
    """Determine whether a rule is meant to be visited by a linter aspect

    Args:
        rule: a [rules_attributes](https://bazel.build/rules/lib/builtins/rule_attributes.html) object
        allow_kinds (list of string): return true if the rule's kind is in the list
        allow_filegroup_tags (list of string): return true if the rule is a filegroup and has a tag in this list

    Returns:
        whether to apply the aspect on this rule
    """
    if rule.kind in allow_kinds:
        return True
    if rule.kind == "filegroup":
        for allow_tag in allow_filegroup_tags:
            if allow_tag in rule.attr.tags:
                return True
    return False

_OUTFILE_FORMAT = "{label}.{mnemonic}.{suffix}"

def output_files(mnemonic, target, ctx):
    """Declare linter output files.

    Args:
        mnemonic: used as part of the filename
        target: the target being visited by a linter aspect
        ctx: the aspect context

    Returns:
        tuple of struct() of output files, and the OutputGroupInfo provider that the rule should return
    """
    human_out = ctx.actions.declare_file(_OUTFILE_FORMAT.format(label = target.label.name, mnemonic = mnemonic, suffix = "out"))

    # NB: named ".report" as there are existing callers depending on that
    machine_out = ctx.actions.declare_file(_OUTFILE_FORMAT.format(label = target.label.name, mnemonic = mnemonic, suffix = "report"))

    if ctx.attr._options[LintOptionsInfo].fail_on_violation:
        # Fail on violation means the exit code is reported to Bazel as the action result
        human_exit_code = None
        machine_exit_code = None
    else:
        # The exit codes should instead be provided as action outputs so the build succeeds.
        # Downstream tooling like `aspect lint` will be responsible for reading the exit codes
        # and interpreting them.
        human_exit_code = ctx.actions.declare_file(_OUTFILE_FORMAT.format(label = target.label.name, mnemonic = mnemonic, suffix = "out.exit_code"))
        machine_exit_code = ctx.actions.declare_file(_OUTFILE_FORMAT.format(label = target.label.name, mnemonic = mnemonic, suffix = "report.exit_code"))

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
    ), OutputGroupInfo(
        rules_lint_human = depset(human_outputs),
        rules_lint_machine = depset(machine_outputs),
        # Legacy name used by existing callers.
        # TODO(2.0): remove
        rules_lint_report = depset(machine_outputs),
    )

def patch_file(mnemonic, target, ctx):
    patch = ctx.actions.declare_file(_OUTFILE_FORMAT.format(label = target.label.name, mnemonic = mnemonic, suffix = "patch"))
    return patch, OutputGroupInfo(rules_lint_patch = depset([patch]))

# If we return multiple OutputGroupInfo from a rule implementation, only one will get used.
# So we need a separate function to return both.
# buildifier: disable=function-docstring
def patch_and_output_files(*args):
    patch, _ = patch_file(*args)
    outputs, _ = output_files(*args)
    human_outputs = [outputs.human.out, outputs.human.exit_code]
    machine_outputs = [outputs.machine.out, outputs.machine.exit_code]
    return struct(
        human = outputs.human,
        machine = outputs.machine,
        patch = patch,
    ), OutputGroupInfo(
        rules_lint_human = depset(human_outputs),
        rules_lint_machine = depset(machine_outputs),
        rules_lint_patch = depset([patch]),
        # Legacy name used by existing callers.
        # TODO(2.0): remove
        rules_lint_report = depset(machine_outputs),
    )

def filter_srcs(rule):
    if "lint-genfiles" in rule.attr.tags:
        return rule.files.srcs
    else:
        return [s for s in rule.files.srcs if s.is_source]

def noop_lint_action(ctx, outputs):
    """Action that creates expected outputs when no files are provided to a lint action.

    This is needed for linters that error when they are given no srcs to inspect.
    It is also a performance optimisation in other cases.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        outputs: struct returned from output_files or patch_and_output_files
    """
    commands = []
    commands.append("touch {}".format(outputs.human.out.path))
    commands.append("touch {}".format(outputs.machine.out.path))

    # NB: if we write JSON machine-readable outputs, then an empty file won't be appropriate
    commands.append("echo 0 > {}".format(outputs.human.exit_code.path))
    commands.append("echo 0 > {}".format(outputs.machine.exit_code.path))

    outs = [outputs.human.out, outputs.human.exit_code, outputs.machine.out, outputs.machine.exit_code]
    if hasattr(outputs, "patch"):
        commands.append("touch {}".format(outputs.patch.path))
        outs.append(outputs.patch)

    ctx.actions.run_shell(
        inputs = [],
        outputs = outs,
        command = " && ".join(commands),
    )
