load("@rules_lint//format:defs.bzl", "format_multirun")

package(default_visibility = ["//:__subpackages__"])

format_multirun(
    name = "format",
    c = "@llvm_toolchain_llvm//:bin/clang-format",
    cc = "@llvm_toolchain_llvm//:bin/clang-format",
    cuda = "@llvm_toolchain_llvm//:bin/clang-format",
    visibility = ["//:__subpackages__"],
)
