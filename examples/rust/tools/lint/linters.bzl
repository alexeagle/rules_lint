"Define linter aspects"

load("@rules_lint//lint:lint_test.bzl", "lint_test")
load("@rules_lint_rust//:clippy.bzl", "lint_clippy_aspect")

clippy = lint_clippy_aspect(
    config = Label("//:.clippy.toml"),
)

clippy_test = lint_test(aspect = clippy)
