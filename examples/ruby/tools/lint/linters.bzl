"Define Ruby linter aspects"

load("@rules_lint//lint:lint_test.bzl", "lint_test")
load("@rules_lint//lint:rubocop.bzl", "lint_rubocop_aspect")
load("@rules_lint//lint:standardrb.bzl", "lint_standardrb_aspect")

rubocop = lint_rubocop_aspect(
    binary = Label("//tools/lint:rubocop"),
    configs = [Label("//:.rubocop.yml")],
)

rubocop_test = lint_test(aspect = rubocop)

standardrb = lint_standardrb_aspect(
    binary = Label("//tools/lint:standardrb"),
    configs = [Label("//:.standard.yml")],
)

standardrb_test = lint_test(aspect = standardrb)
