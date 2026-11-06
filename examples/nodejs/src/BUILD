load("@rules_lint//format:defs.bzl", "format_test")
load("@aspect_rules_swc//swc:defs.bzl", "swc")
load("@aspect_rules_ts//ts:defs.bzl", "ts_config", "ts_project")
load("@bazel_skylib//lib:partial.bzl", "partial")
load("//tools/lint:linters.bzl", "eslint_test", "oxlint_test")

package(default_visibility = ["//visibility:public"])

exports_files(["oxlint-typed.json"])

ts_config(
    name = "tsconfig",
    src = ":tsconfig.json",
)

filegroup(
    name = "css",
    srcs = ["hello.css"],
    tags = ["lint-with-stylelint"],
)

filegroup(
    name = "clean_css",
    srcs = ["clean.css"],
    tags = ["lint-with-stylelint"],
)

filegroup(
    name = "less",
    srcs = ["hello.less"],
    tags = ["lint-with-stylelint"],
)

filegroup(
    name = "oxlint_fixable",
    srcs = ["oxlint-fixable.ts"],
    tags = ["lint-with-oxlint"],
)

oxlint_test(
    name = "oxlint_fixable_test",
    srcs = [":oxlint_fixable"],
    expected_exit_code = 1,
)

filegroup(
    name = "scss",
    srcs = ["hello.scss"],
    tags = ["lint-with-stylelint"],
)

filegroup(
    name = "md",
    srcs = ["README.md"],
    tags = ["markdown"],
)

ts_project(
    name = "ts_dep",
    srcs = ["file-dep.ts"],
    declaration = True,
    transpiler = "tsc",
    tsconfig = ":tsconfig",
    deps = [],
)

ts_project(
    name = "ts",
    srcs = ["file.ts"],
    declaration = True,
    transpiler = partial.make(
        swc,
        swcrc = "//:.swcrc",
    ),
    deps = [
        ":ts_dep",
        "//:node_modules/dayjs",
    ],
)

# Regression test for https://github.com/aspect-build/rules_lint/issues/368
eslint_test(
    name = "eslint_empty_report",
    srcs = [":ts"],
)

format_test(
    name = "format_js_test",
    srcs = [
        "(special_char)/[square]/hello.md",
        "(special_char)/[square]/hello.ts",
    ],
    javascript = "//tools/format:prettier",
    markdown = "//tools/format:prettier",
)
