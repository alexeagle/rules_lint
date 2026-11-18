load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_binary(
    name = "hello_cc",
    srcs = ["hello.cpp"],
)

cc_library(
    name = "stdlib_check",
    srcs = ["stdlib_check.cpp"],
    # -stdlib=libc++ selects the libc++ standard library implementation,
    # matching the toolchains_llvm configuration from issue #566.
    # On macOS, clang-tidy needs -isysroot to find the Xcode SDK
    # platform headers (wchar.h, stdlib.h, math.h) that libc++ depends on.
    copts = ["-stdlib=libc++"],
)

filegroup(
    name = "all",
    srcs = [
        "hello.cu",
        ":hello_cc",
        "//src/cpp/main:hello-world",
    ],
)
