# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_test")
load("//test:machine_output.bzl", "machine_eslint_report", "machine_oxlint_report", "machine_stylelint_report")
load("//tools/lint:linters.bzl", "eslint_test", "oxlint_test", "stylelint_test")

eslint_test(
    name = "eslint_empty_report",
    srcs = ["//src:ts"],
)

stylelint_test(
    name = "stylelint_no_violations",
    srcs = ["//src:clean_css"],
)

machine_eslint_report(
    name = "machine_eslint_report",
    src = "//src:ts",
)

report_test(
    name = "eslint_machine_output_test",
    expected_tool = "ESLint",
    expected_uri = "src/file.ts",
    report = "machine_eslint_report",
)

oxlint_test(
    name = "oxlint_fixable",
    srcs = ["//src:oxlint_fixable"],
    expected_exit_code = 1,
)

machine_oxlint_report(
    name = "machine_oxlint_report",
    src = "//src:oxlint_fixable",
)

report_test(
    name = "oxlint_machine_output_test",
    expected_tool = "oxlint",
    expected_uri = "src/oxlint-fixable.ts",
    report = "machine_oxlint_report",
)

machine_stylelint_report(
    name = "machine_stylelint_report",
    src = "//src:css",
)

report_test(
    name = "stylelint_machine_output_test",
    expected_tool = "Stylelint",
    expected_uri = "src/hello.css",
    report = "machine_stylelint_report",
)
