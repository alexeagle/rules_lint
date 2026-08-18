"Extracts the machine-readable SARIF report from a target that has been linted with rules_lint."

# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "machine_report_rule")
load("//tools/lint:linters.bzl", "eslint", "oxlint", "stylelint")

machine_eslint_report = machine_report_rule(eslint)
machine_oxlint_report = machine_report_rule(oxlint)
machine_stylelint_report = machine_report_rule(stylelint)
