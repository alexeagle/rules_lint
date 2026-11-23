load("@bazel_skylib//rules:native_binary.bzl", "native_binary")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//:__subpackages__"])

native_binary(
    name = "clang_tidy",
    src = select(
        {
            "@bazel_tools//src/conditions:linux_x86_64": "@llvm_toolchain_llvm//:bin/clang-tidy",
            "@bazel_tools//src/conditions:linux_aarch64": "@llvm_toolchain_llvm//:bin/clang-tidy",
            "@bazel_tools//src/conditions:darwin_x86_64": "@llvm_toolchain_llvm//:bin/clang-tidy",
            "@bazel_tools//src/conditions:darwin_arm64": "@llvm_toolchain_llvm//:bin/clang-tidy",
            # llvm_toolchain doesn't support windows: https://github.com/bazel-contrib/toolchains_llvm/issues/4
            # as a workaround, you can download exes from
            # https://github.com/llvm/llvm-project/releases/tag/llvmorg-18.1.6 and make available locally.
            "@bazel_tools//src/conditions:windows_x64": "clang-tidy.exe",
        },
    ),
    # Combined LLVM drivers may dispatch by executable name; preserve clang-tidy.
    out = select({
        "@platforms//os:windows": "clang-tidy.exe",
        "//conditions:default": "clang-tidy",
    }),
)

# cppcheck
genrule(
    name = "cppcheck_wrapper",
    srcs = ["cppcheck_wrapper.sh.tpl"],
    outs = ["cppcheck_wrapper.sh"],
    cmd = "cp $(location cppcheck_wrapper.sh.tpl) $@",
)

sh_binary(
    name = "cppcheck",
    srcs = [":cppcheck_wrapper"],
    data = select({
        "@platforms//os:linux": ["@cppcheck_linux//:files"],
        "@platforms//os:macos": ["@cppcheck_macos//:files"],
    }),
)
