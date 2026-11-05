# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_test")
load("//test:machine_output.bzl", "machine_buildifier_report")
load("//tools/lint:linters.bzl", "buildifier_test")

package(default_visibility = ["//visibility:public"])

buildifier_test(
    name = "buildifier_bzl_library",
    srcs = ["//src:defs"],
    expected_exit_code = 4,
)

buildifier_test(
    name = "buildifier_tagged_target",
    srcs = ["//src:tagged_starlark"],
    expected_exit_code = 4,
)

buildifier_test(
    name = "buildifier_clean_target",
    srcs = ["//src:clean_starlark"],
)

machine_buildifier_report(
    name = "machine_buildifier_report",
    src = "//src:defs",
)

machine_buildifier_report(
    name = "machine_buildifier_tagged_report",
    src = "//src:tagged_starlark",
)

report_test(
    name = "buildifier_machine_output_test",
    expected_tool = "Buildifier",
    expected_uri = "src/defs.bzl",
    report = "machine_buildifier_report",
)

report_test(
    name = "buildifier_tagged_machine_output_test",
    expected_tool = "Buildifier",
    expected_uri = "src/custom.star",
    report = "machine_buildifier_tagged_report",
)
