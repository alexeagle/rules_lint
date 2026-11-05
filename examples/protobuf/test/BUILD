# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_test")
load("//test:machine_output.bzl", "machine_buf_report")
load("//tools/lint:linters.bzl", "buf_test")

package(default_visibility = ["//visibility:public"])

buf_test(
    name = "buf",
    srcs = ["//src:foo_proto"],
    expected_exit_code = 1,
)

machine_buf_report(
    name = "machine_buf_report",
    src = "//src:foo_proto",
)

report_test(
    name = "buf_machine_output_test",
    expected_tool = "Buf",
    expected_uri = "src/file.proto",
    report = "machine_buf_report",
)
