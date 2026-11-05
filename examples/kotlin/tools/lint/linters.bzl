"Define Kotlin linter aspects"

load("@rules_lint//lint:ktlint.bzl", "lint_ktlint_aspect")
load("@rules_lint//lint:lint_test.bzl", "lint_test")

ktlint = lint_ktlint_aspect(
    binary = Label("@com_github_pinterest_ktlint//file"),
    editorconfig = Label("//:.editorconfig"),
    baseline_file = Label("//:ktlint-baseline.xml"),
)

ktlint_test = lint_test(aspect = ktlint)
