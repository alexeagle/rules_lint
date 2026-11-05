# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_test")
load("//test:machine_output.bzl", "machine_taplo_report")
load("//tools/lint:linters.bzl", "taplo_test")

package(default_visibility = ["//visibility:public"])

taplo_test(
    name = "taplo_bad",
    srcs = ["//src:bad"],
    expected_exit_code = 1,
)

taplo_test(
    name = "taplo_hello",
    srcs = ["//src:hello"],
)

machine_taplo_report(
    name = "machine_taplo_report",
    src = "//src:bad",
)

report_test(
    name = "taplo_machine_output_test",
    expected_tool = "Taplo",
    expected_uri = "src/bad.toml",
    report = "machine_taplo_report",
)
