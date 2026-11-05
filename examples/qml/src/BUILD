load("@rules_lint//format:defs.bzl", "format_test")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "qml",
    srcs = ["Main.qml"],
    tags = ["qml"],
)

filegroup(
    name = "all",
    srcs = [":qml"],
)

format_test(
    name = "format_files_test",
    srcs = ["Main.qml"],
    qml = "//tools/format:qmlformat",
)
