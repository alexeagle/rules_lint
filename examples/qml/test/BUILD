# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_test")
load("//test:machine_output.bzl", "machine_qmllint_report")
load("//tools/lint:linters.bzl", "qmllint_test")

package(default_visibility = ["//visibility:public"])

qmllint_test(
    name = "qmllint",
    srcs = ["//src:qml"],
    expected_exit_code = 255,
)

machine_qmllint_report(
    name = "machine_qmllint_report",
    src = "//src:qml",
)

report_test(
    name = "qmllint_machine_output_test",
    expected_tool = "Qmllint",
    expected_uri = "src/Main.qml",
    report = "machine_qmllint_report",
)
