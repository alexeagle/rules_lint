"C++-specific machine report rules for testing."

# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "machine_report_rule")
load("//tools/lint:linters.bzl", "clang_tidy", "cppcheck")

machine_clang_tidy_report = machine_report_rule(clang_tidy)

machine_cppcheck_report = machine_report_rule(cppcheck)
