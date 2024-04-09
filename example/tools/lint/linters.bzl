"Define linter aspects"

load("@aspect_rules_lint//lint:buf.bzl", "lint_buf_aspect")
load("@aspect_rules_lint//lint:eslint.bzl", "lint_eslint_aspect")
load("@aspect_rules_lint//lint:flake8.bzl", "lint_flake8_aspect")
load("@aspect_rules_lint//lint:golangci-lint.bzl", "lint_golangci_aspect")
load("@aspect_rules_lint//lint:lint_test.bzl", "lint_test")
load("@aspect_rules_lint//lint:pmd.bzl", "lint_pmd_aspect")
load("@aspect_rules_lint//lint:ruff.bzl", "lint_ruff_aspect")
load("@aspect_rules_lint//lint:shellcheck.bzl", "lint_shellcheck_aspect")
load("@aspect_rules_lint//lint:vale.bzl", "lint_vale_aspect")

buf = lint_buf_aspect(
    config = "@@//:buf.yaml",
)

eslint = lint_eslint_aspect(
    binary = "@@//tools/lint:eslint",
    # We trust that eslint will locate the correct configuration file for a given source file.
    # See https://eslint.org/docs/latest/use/configure/configuration-files#cascading-and-hierarchy
    configs = [
        "@@//:eslintrc",
        "@@//src/subdir:eslintrc",
    ],
)

eslint_test = lint_test(aspect = eslint)

flake8 = lint_flake8_aspect(
    binary = "@@//tools/lint:flake8",
    config = "@@//:.flake8",
)

flake8_test = lint_test(aspect = flake8)

pmd = lint_pmd_aspect(
    binary = "@@//tools/lint:pmd",
    rulesets = ["@@//:pmd.xml"],
)

pmd_test = lint_test(aspect = pmd)

ruff = lint_ruff_aspect(
    binary = "@@//tools/lint:ruff",
    configs = [
        "@@//:.ruff.toml",
        "@@//src/subdir:ruff.toml",
    ],
)

ruff_test = lint_test(aspect = ruff)

shellcheck = lint_shellcheck_aspect(
    binary = "@multitool//tools/shellcheck",
    config = "@@//:.shellcheckrc",
)

shellcheck_test = lint_test(aspect = shellcheck)

golangci_lint = lint_golangci_aspect(
    binary = "@multitool//tools/golangci-lint",
    config = "@@//:.golangci.yaml",
)

golangci_lint_test = lint_test(aspect = golangci_lint)

vale = lint_vale_aspect(
    binary = "@@//tools/lint:vale",
    config = "@@//:.vale.ini",
    styles = "@@//tools/lint:vale_styles",
)
