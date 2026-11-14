"Regression fixture for Ruff diagnostics in fix mode."

load("//lint:ruff.bzl", "lint_ruff_aspect")

_ruff = lint_ruff_aspect(
    binary = Label("//lint/test:ruff_failure"),
    configs = [],
)

def _fix_mode_impl(_settings, _attr):
    return {"//lint:fix": True}

_fix_mode = transition(
    implementation = _fix_mode_impl,
    inputs = [],
    outputs = ["//lint:fix"],
)

def _reports_impl(ctx):
    target = ctx.attr.src[0]
    groups = target[OutputGroupInfo]
    return [DefaultInfo(files = depset(transitive = [groups.rules_lint_human, groups.rules_lint_patch]))]

ruff_fix_reports = rule(
    implementation = _reports_impl,
    attrs = {
        "src": attr.label(aspects = [_ruff], cfg = _fix_mode),
        "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
    },
)
