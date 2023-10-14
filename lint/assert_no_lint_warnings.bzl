"""Factory function to make lint test rules.

The test will fail when the linter reports any non-empty lint results.

To use this, in your `lint.bzl` where you define the aspect, just create a test that references it.

For example, with `flake8`:

```starlark
load("@aspect_rules_lint//lint:assert_no_lint_warnings.bzl", "assert_no_lint_warnings")
load("@aspect_rules_lint//lint:flake8.bzl", "flake8_aspect")

flake8 = flake8_aspect(
    binary = "@@//:flake8",
    config = "@@//:.flake8",
)

flake8_test = assert_no_lint_warnings(aspect = flake8)
```

Now in your BUILD files you can add a test:

```starlark
load("//tools:lint.bzl", "flake8_test")

py_library(
    name = "unused_import",
    srcs = ["unused_import.py"],
)

flake8_test(
    name = "flake8",
    srcs = [":unused_import"],
)
```
"""

load("@aspect_bazel_lib//lib:paths.bzl", "to_rlocation_path")

def _test_impl(ctx):
    reports = []
    for src in ctx.attr.srcs:
        for report in src[OutputGroupInfo].report.to_list():
            reports.append(report)

    bin = ctx.actions.declare_file("assert_no_lint_warnings.sh")
    ctx.actions.expand_template(
        template = ctx.file._bin,
        output = bin,
        substitutions = {"{{reports}}": " ".join([to_rlocation_path(ctx, r) for r in reports])},
        is_executable = True,
    )
    return [DefaultInfo(
        executable = bin,
        runfiles = ctx.runfiles(reports + [ctx.file._runfiles_lib]),
    )]

def assert_no_lint_warnings(aspect):
    return rule(
        implementation = _test_impl,
        attrs = {
            "srcs": attr.label_list(doc = "*_library targets", aspects = [aspect]),
            "fail_on_violation": attr.bool(),
            "_bin": attr.label(default = ":assert_no_lint_warnings.sh", allow_single_file = True, executable = True, cfg = "exec"),
            "_runfiles_lib": attr.label(default = "@bazel_tools//tools/bash/runfiles", allow_single_file = True),
        },
        test = True,
    )
