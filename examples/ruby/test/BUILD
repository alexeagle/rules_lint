"Demonstrates how to enforce zero-lint-tolerance policy with tests"

# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_test")  # @unused: used in commented-out tests
load(
    "//tools/lint:linters.bzl",
    "rubocop_test",
    "standardrb_test",
)
load(
    ":machine_output.bzl",
    "machine_rubocop_report",
    "machine_standardrb_report",
)

rubocop_test(
    name = "rubocop",
    srcs = ["//src:hello_ruby"],
    expected_exit_code = 1,
)

standardrb_test(
    name = "standardrb",
    srcs = ["//src:hello_ruby"],
    expected_exit_code = 1,
)

machine_rubocop_report(
    name = "machine_rubocop_report",
    src = "//src:hello_ruby",
)

# report_test(
#     name = "rubocop_machine_output_test",
#     expected_tool = "RuboCop",
#     expected_uri = "src/hello.rb",
#     report = "machine_rubocop_report",
# )

machine_standardrb_report(
    name = "machine_standardrb_report",
    src = "//src:hello_ruby",
)

# report_test(
#     name = "standardrb_machine_output_test",
#     expected_tool = "Standard",
#     expected_uri = "src/hello.rb",
#     report = "machine_standardrb_report",
# )
