"Setup keep-sorted linter"

load("@rules_lint//lint:keep_sorted.bzl", "lint_keep_sorted_aspect")
load("@rules_lint//lint:lint_test.bzl", "lint_test")

keep_sorted = lint_keep_sorted_aspect(
    binary = Label("@com_github_google_keep_sorted//:keep-sorted"),
)

keep_sorted_test = lint_test(aspect = keep_sorted)
