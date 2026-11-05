"Extract machine report rules for testing."

# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "machine_report_rule")
load("//tools/lint:linters.bzl", "keep_sorted")

machine_keep_sorted_report = machine_report_rule(keep_sorted)
