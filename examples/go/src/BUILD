load("@rules_lint//format:defs.bzl", "format_test")
load("@rules_go//go:def.bzl", "go_binary")

package(default_visibility = ["//visibility:public"])

go_binary(
    name = "hello",
    srcs = ["hello.go"],
)

# Cause a test failure when files are not formatted.
# This is useful when you have no other way to check formatting on CI; see documentation.
format_test(
    name = "format_files_test",
    srcs = ["hello.go"],
)
