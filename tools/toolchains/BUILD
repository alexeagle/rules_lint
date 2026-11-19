load("@bazel_lib//:bzl_library.bzl", "bzl_library")

package(default_visibility = ["//visibility:public"])

toolchain_type(name = "sarif_parser_toolchain_type")

bzl_library(
    name = "sarif_parser_toolchain",
    srcs = ["sarif_parser_toolchain.bzl"],
    deps = [
        "//tools:integrity",
        "//tools:version",
    ],
)

toolchain_type(name = "gopackagesdriver_toolchain_type")

bzl_library(
    name = "gopackagesdriver_toolchain",
    srcs = ["gopackagesdriver_toolchain.bzl"],
    deps = [
        "//tools:integrity",
        "//tools:version",
    ],
)
