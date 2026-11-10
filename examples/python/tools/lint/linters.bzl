"Define Python linter aspects"

load("@rules_lint//lint:bandit.bzl", "lint_bandit_aspect")
load("@rules_lint//lint:flake8.bzl", "lint_flake8_aspect")
load("@rules_lint//lint:lint_test.bzl", "lint_test")
load("@rules_lint//lint:pydoclint.bzl", "lint_pydoclint_aspect")
load("@rules_lint//lint:pylint.bzl", "lint_pylint_aspect")
load("@rules_lint//lint:ruff.bzl", "lint_ruff_aspect")
load("@rules_lint//lint:ty.bzl", "lint_ty_aspect")

bandit = lint_bandit_aspect(
    binary = Label("//tools/lint:bandit"),
    config = Label("//:pyproject.toml"),
)

bandit_test = lint_test(aspect = bandit)

flake8 = lint_flake8_aspect(
    binary = Label("//tools/lint:flake8"),
    config = Label("//:.flake8"),
)

flake8_test = lint_test(aspect = flake8)

pylint = lint_pylint_aspect(
    binary = Label("//tools/lint:pylint"),
    config = Label("//:.pylintrc"),
)

pylint_test = lint_test(aspect = pylint)

pydoclint = lint_pydoclint_aspect(
    binary = Label("//tools/lint:pydoclint"),
    config = Label("//:pyproject.toml"),
)

pydoclint_test = lint_test(aspect = pydoclint)

ruff = lint_ruff_aspect(
    binary = Label("@rules_lint//lint:ruff_bin"),
    configs = [
        Label("@//:pyproject.toml"),
        Label("@//src:ruff.toml"),
        Label("@//src/first_party_imports:ruff.toml"),
        Label("@//src/subdir:ruff.toml"),
    ],
)

ruff_test = lint_test(aspect = ruff)

ty = lint_ty_aspect(
    binary = Label("@rules_lint//lint:ty_bin"),
    config = Label("@//:pyproject.toml"),
)

ty_test = lint_test(aspect = ty)
