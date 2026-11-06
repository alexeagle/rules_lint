"Define Node.js linter aspects"

load("@rules_lint//lint:eslint.bzl", "lint_eslint_aspect")
load("@rules_lint//lint:lint_test.bzl", "lint_test")
load("@rules_lint//lint:oxlint.bzl", "lint_oxlint_aspect")
load("@rules_lint//lint:stylelint.bzl", "lint_stylelint_aspect")
load("@rules_lint//lint:vale.bzl", "lint_vale_aspect")

eslint = lint_eslint_aspect(
    binary = Label("//tools/lint:eslint"),
    # ESLint will resolve the configuration file by looking in the working directory first.
    # See https://eslint.org/docs/latest/use/configure/configuration-files#configuration-file-resolution
    # We must also include any other config files we expect eslint to be able to locate, e.g. tsconfigs
    configs = [
        Label("//:eslintrc"),
    ],
)

eslint_test = lint_test(aspect = eslint)

oxlint = lint_oxlint_aspect(
    binary = Label("//tools/lint:oxlint"),
    config = Label("//:oxlint_config"),
    fix_binary = Label("//tools/lint:oxlint_for_fix"),
)

oxlint_test = lint_test(aspect = oxlint)

oxlint_typed = lint_oxlint_aspect(
    binary = Label("//tools/lint:oxlint"),
    config = Label("//src:oxlint-typed.json"),
    type_aware = True,
    tsgolint = Label("//tools/lint:tsgolint"),
)

oxlint_typed_test = lint_test(aspect = oxlint_typed)

stylelint = lint_stylelint_aspect(
    binary = Label("//tools/lint:stylelint"),
    config = Label("//:stylelintrc"),
)

stylelint_test = lint_test(aspect = stylelint)

vale = lint_vale_aspect(
    binary = Label("//tools/lint:vale"),
    config = Label("//:.vale.ini"),
    styles = Label("//tools/lint:vale_styles"),
)

vale_test = lint_test(aspect = vale)
