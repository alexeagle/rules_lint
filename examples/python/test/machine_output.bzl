"Python-specific lint report rules for testing."

# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "machine_report_rule")
load("//tools/lint:linters.bzl", "bandit", "flake8", "pydoclint", "pylint", "ruff", "ty")

machine_bandit_report = machine_report_rule(bandit)

machine_ruff_report = machine_report_rule(ruff)

machine_ty_report = machine_report_rule(ty)

machine_flake8_report = machine_report_rule(flake8)

machine_pylint_report = machine_report_rule(pylint)

machine_pydoclint_report = machine_report_rule(pydoclint)

def _ty_human_report_impl(ctx):
    return [DefaultInfo(files = ctx.attr.src[OutputGroupInfo].rules_lint_human)]

ty_human_report = rule(
    implementation = _ty_human_report_impl,
    attrs = {"src": attr.label(aspects = [ty])},
)
