"Java-specific machine report rules for testing."

# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "machine_report_rule")
load("//tools/lint:linters.bzl", "checkstyle", "pmd", "spotbugs")

machine_pmd_report = machine_report_rule(pmd)

machine_checkstyle_report = machine_report_rule(checkstyle)

machine_spotbugs_report = machine_report_rule(spotbugs)
