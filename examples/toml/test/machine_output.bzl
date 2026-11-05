"TOML-specific machine report rules for testing."

# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "machine_report_rule")
load("//tools/lint:linters.bzl", "taplo")

machine_taplo_report = machine_report_rule(taplo)
