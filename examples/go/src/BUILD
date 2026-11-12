load("@rules_go//go:def.bzl", "go_binary", "go_library")
load("@rules_lint//format:defs.bzl", "format_test")

package(default_visibility = ["//visibility:public"])

go_binary(
    name = "hello",
    srcs = ["hello.go"],
)

# A clean library used to assert golangci-lint reports no false positives.
go_library(
    name = "greeting",
    srcs = ["greeting.go"],
    importpath = "github.com/aspect-build/rules_lint/examples/go/src/greeting",
)

# Cause a test failure when files are not formatted.
# This is useful when you have no other way to check formatting on CI; see documentation.
format_test(
    name = "format_files_test",
    srcs = [
        "greeting.go",
        "hello.go",
    ],
)
