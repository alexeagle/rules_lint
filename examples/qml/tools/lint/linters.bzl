"Define QML linter aspects"

load("@rules_lint//lint:lint_test.bzl", "lint_test")
load("@rules_lint//lint:qmllint.bzl", "lint_qmllint_aspect")

qmllint = lint_qmllint_aspect(
    binary = Label("//tools/lint:qmllint"),
    config = Label("//:.qmllint.ini"),
)

qmllint_test = lint_test(aspect = qmllint)
