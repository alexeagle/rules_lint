"Define YAML linter aspects"

load("@rules_lint//lint:lint_test.bzl", "lint_test")
load("@rules_lint//lint:yamllint.bzl", "lint_yamllint_aspect")

yamllint = lint_yamllint_aspect(
    binary = Label("//tools/lint:yamllint"),
    config = Label("//:.yamllint"),
)

yamllint_test = lint_test(aspect = yamllint)
