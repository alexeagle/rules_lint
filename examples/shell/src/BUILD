load("@rules_lint//format:defs.bzl", "format_test")
load("@rules_shell//shell:sh_library.bzl", "sh_library")

package(default_visibility = ["//visibility:public"])

sh_library(
    name = "hello",
    srcs = ["hello.sh"],
)

sh_library(
    name = "sourced_dep",
    srcs = ["sourced_dep.sh"],
)

sh_library(
    name = "sourced_main",
    srcs = ["sourced_main.sh"],
    deps = [":sourced_dep"],
)

# Cause a test failure when files are not formatted.
# This is useful when you have no other way to check formatting on CI; see documentation.
format_test(
    name = "format_files_test",
    srcs = [
        "hello.sh",
        "sourced_dep.sh",
        "sourced_main.sh",
    ],
)
