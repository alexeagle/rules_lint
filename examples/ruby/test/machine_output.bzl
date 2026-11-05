"Ruby-specific machine report rules for testing."

# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "machine_report_rule")
load("//tools/lint:linters.bzl", "rubocop", "standardrb")

machine_rubocop_report = machine_report_rule(rubocop)

machine_standardrb_report = machine_report_rule(standardrb)
