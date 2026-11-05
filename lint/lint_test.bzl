"""Factory function to make lint test rules.

When the linter exits non-zero, the test will print the output of the linter and then fail.
The test also writes JUnit XML with a testcase per linted target and the linter output in its
`<failure>`, so CI systems that read the XML can show the violations.

To use this, in your `linters.bzl` where you define the aspect, just create a test that references it.

For example, with `flake8`:

```starlark
load("@rules_lint//lint:lint_test.bzl", "lint_test")
load("@rules_lint//lint:flake8.bzl", "lint_flake8_aspect")

flake8 = lint_flake8_aspect(
    binary = Label("//:flake8"),
    config = Label("//:.flake8"),
)

flake8_test = lint_test(aspect = flake8)
```

Now in your BUILD files you can add a test:

```starlark
load("//tools/lint:linters.bzl", "flake8_test")

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

load("@bazel_lib//lib:paths.bzl", "to_rlocation_path")
load("@bazel_lib//lib:windows_utils.bzl", "create_windows_native_launcher_script")

def _sh_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

def _display_label(label):
    "The label as users write it, e.g. //pkg:name rather than @@//pkg:name"
    s = str(label)
    return s[2:] if s.startswith("@@//") else s

def _write_assert(ctx, label, files):
    "Create a parameter to substitute into the shell script"
    outputs = []
    exit_codes = []
    for f in files.to_list():
        if f.path.endswith(".out"):
            outputs.append(f)
        elif f.path.endswith(".exit_code"):
            exit_codes.append(f)
        else:
            fail("rules_lint_human output group contains unrecognized file extension: ", f.path)
    if outputs and exit_codes:
        if len(outputs) != len(exit_codes):
            fail("mismatch between outputs and exit_codes", outputs, exit_codes)
        return ["assert_exit_code {} {} {}".format(_sh_quote(to_rlocation_path(ctx, e)), _sh_quote(to_rlocation_path(ctx, o)), _sh_quote(_display_label(label))) for e, o in zip(exit_codes, outputs)]
    if outputs:
        return ["assert_output_empty {} {}".format(_sh_quote(to_rlocation_path(ctx, o)), _sh_quote(_display_label(label))) for o in outputs]
    fail("missing output file among", files)

def _reports(ctx, src):
    "The report files the aspect produced for one of the srcs"
    if OutputGroupInfo not in src or not hasattr(src[OutputGroupInfo], "rules_lint_human"):
        fail("""\
{test}: the lint aspect produced no report for {src}, so there is nothing to assert on.
The aspect did not run on that target. Either its rule kind is not one the aspect visits, \
it is tagged "no-lint", or it does not advertise a provider the aspect requires \
(clippy: the target is built by a different rules_rust than the lint module loads).""".format(
            test = ctx.label,
            src = src.label,
        ))
    return src[OutputGroupInfo].rules_lint_human

def _test_impl(ctx):
    bin = ctx.actions.declare_file("{}.lint_test.sh".format(ctx.label.name))
    reports = [(src.label, _reports(ctx, src)) for src in ctx.attr.srcs]
    asserts = [a for label, files in reports for a in _write_assert(ctx, label, files)]

    runfiles = ctx.runfiles(transitive_files = depset(transitive = [files for _, files in reports]))
    runfiles = runfiles.merge(ctx.attr._runfiles_lib[DefaultInfo].default_runfiles)

    ctx.actions.expand_template(
        template = ctx.file._bin,
        output = bin,
        substitutions = {
            "{{asserts}}": "\n".join(asserts),
            "{{expected_exit_code}}": str(ctx.attr.expected_exit_code),
        },
        is_executable = True,
    )

    if ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]):
        launcher = create_windows_native_launcher_script(ctx, bin)
        runfiles = runfiles.merge(ctx.runfiles(files = [bin]))
    else:
        launcher = bin

    return [DefaultInfo(
        executable = launcher,
        runfiles = runfiles,
    )]

def lint_test(aspect):
    return rule(
        implementation = _test_impl,
        attrs = {
            "srcs": attr.label_list(doc = "*_library targets", aspects = [aspect]),
            "expected_exit_code": attr.int(default = 0, doc = """\
                The expected exit code of the linter.
                Default is 0, which means the test will fail if the linter reports any issues.
                Set to a different value if you are testing that the linter correctly reports an issue.
            """),
            "_bin": attr.label(default = ":lint_test.sh", allow_single_file = True, executable = True, cfg = "exec"),
            "_runfiles_lib": attr.label(default = "@bazel_tools//tools/bash/runfiles"),
            "_windows_constraint": attr.label(default = "@platforms//os:windows"),
        },
        toolchains = ["@bazel_tools//tools/sh:toolchain_type"],
        test = True,
    )
