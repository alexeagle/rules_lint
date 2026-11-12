"Extract golangci-lint reports for diagnostic assertions."

# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "machine_report_rule")
load("//tools/lint:linters.bzl", "golangci_lint_facts")

machine_golangci_lint_facts_report = machine_report_rule(golangci_lint_facts)
