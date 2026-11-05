"Define TOML linter aspects"

load("@rules_lint//lint:lint_test.bzl", "lint_test")
load("@rules_lint//lint:taplo.bzl", "lint_taplo_aspect")

taplo = lint_taplo_aspect(
    binary = Label("//tools/lint:taplo"),
    config = Label("//:.taplo.toml"),
)

taplo_test = lint_test(aspect = taplo)
