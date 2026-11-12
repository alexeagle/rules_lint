"Define linter aspects"

load("@rules_lint//lint:golangci_lint.bzl", "lint_golangci_lint_aspect")
load("@rules_lint//lint:lint_test.bzl", "lint_test")

golangci_lint = lint_golangci_lint_aspect(
    binary = Label("@rules_lint//lint:golangci_lint_bin"),
    config = Label("@//:.golangci.yml"),
)

golangci_lint_test = lint_test(aspect = golangci_lint)

# Isolate fact-producing printf from other linters. The bools analyzer also
# checks that dependency diagnostics are not reported as root diagnostics.
golangci_lint_facts = lint_golangci_lint_aspect(
    binary = Label("@rules_lint//lint:golangci_lint_bin"),
    config = Label("@//test/analyzerfacts:.golangci.yml"),
    mnemonic = "AspectRulesLintGolangciLintFacts",
)

golangci_lint_facts_test = lint_test(aspect = golangci_lint_facts)
