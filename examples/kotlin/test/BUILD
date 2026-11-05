"Demonstrates how to enforce zero-lint-tolerance policy with tests"

# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_test")
load("//tools/lint:linters.bzl", "ktlint_test")
load(":machine_output.bzl", "machine_ktlint_report")

ktlint_test(
    name = "ktlint",
    srcs = ["//src:hello_kt"],
    expected_exit_code = 1,
)

machine_ktlint_report(
    name = "machine_ktlint_report",
    src = "//src:hello_kt",
)

report_test(
    name = "ktlint_machine_output_test",
    expected_tool = "KTLint",
    expected_uri = "src/hello.kt",
    report = "machine_ktlint_report",
)
