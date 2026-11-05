"Define linter aspects"

load("@rules_lint//lint:buf.bzl", "lint_buf_aspect")
load("@rules_lint//lint:lint_test.bzl", "lint_test")

buf = lint_buf_aspect(
    config = Label("@//:buf.yaml"),
)

buf_test = lint_test(aspect = buf)
