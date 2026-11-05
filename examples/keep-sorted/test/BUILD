# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_test")
load("//test:machine_output.bzl", "machine_keep_sorted_report")
load("//tools/lint:linters.bzl", "keep_sorted_test")

package(default_visibility = ["//visibility:public"])

keep_sorted_test(
    name = "keep_sorted",
    srcs = ["//src:example"],
    expected_exit_code = 1,
)

machine_keep_sorted_report(
    name = "machine_report",
    src = "//src:example",
)

report_test(
    name = "machine_output_test",
    expected_tool = "KeepSorted",
    expected_uri = "src/example.go",
    report = "machine_report",
)
