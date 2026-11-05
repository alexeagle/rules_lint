# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_results_count_test", "report_test")
load("//test:machine_output.bzl", "machine_shellcheck_report")
load("//tools/lint:linters.bzl", "shellcheck_test")

package(default_visibility = ["//visibility:public"])

shellcheck_test(
    name = "shellcheck",
    srcs = ["//src:hello"],
    expected_exit_code = 1,
)

shellcheck_test(
    name = "shellcheck_sourced_main",
    srcs = ["//src:sourced_main"],
)

shellcheck_test(
    name = "shellcheck_sourced_dep",
    srcs = ["//src:sourced_dep"],
    expected_exit_code = 1,
)

machine_shellcheck_report(
    name = "machine_shellcheck_report",
    src = "//src:hello",
)

machine_shellcheck_report(
    name = "machine_sourced_main_report",
    src = "//src:sourced_main",
)

machine_shellcheck_report(
    name = "machine_sourced_dep_report",
    src = "//src:sourced_dep",
)

report_test(
    name = "shellcheck_machine_output_test",
    expected_tool = "ShellCheck",
    expected_uri = "src/hello.sh",
    report = "machine_shellcheck_report",
)

report_results_count_test(
    name = "sourced_main_machine_output_empty_test",
    expected_count = 0,
    report = "machine_sourced_main_report",
)

report_test(
    name = "sourced_dep_machine_output_test",
    expected_tool = "ShellCheck",
    expected_uri = "src/sourced_dep.sh",
    report = "machine_sourced_dep_report",
)
