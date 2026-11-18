"""Choose the macOS SDK root that clang-tidy gets as its sysroot."""

# apple_support's toolchain passes `__BAZEL_XCODE_SDKROOT__` in place of the SDK
# root (and `__BAZEL_XCODE_DEVELOPER_DIR__` in place of the Xcode directory).
# Only its own wrapped_clang expands them, at execution time, and clang-tidy
# never runs through that wrapper. A sysroot with such a value is not usable.
# https://github.com/bazelbuild/apple_support/blob/8a5de128485e553bd35b8cd881b43480708f43ec/crosstool/cc_toolchain_config.bzl#L1052-L1053
_XCODE_PLACEHOLDER_PREFIX = "__BAZEL_XCODE_"

def _is_usable(sysroot):
    return bool(sysroot) and _XCODE_PLACEHOLDER_PREFIX not in sysroot

def macos_sysroot_args(flags, toolchain_sysroot, built_in_include_directories):
    """Return the `-isysroot` arguments that clang-tidy needs on macOS.

    A sysroot that the flags already pin wins, whether it comes from the
    toolchain, the command line or the target. clang uses the last
    `-isysroot`, and `--sysroot` only if there is no `-isysroot`:
    https://github.com/llvm/llvm-project/blob/llvmorg-16.0.4/clang/lib/Driver/ToolChains/Darwin.cpp#L2297-L2311
    So one more `-isysroot` overrides all the others. This function adds it
    only if clang would otherwise use no sysroot or an apple_support
    placeholder.

    Args:
        flags: the compiler flags of the toolchain, the command line and the
            target, in the order clang gets them. A sysroot flag can have its
            directory in the same item (`-isysroot<dir>`, `--sysroot=<dir>`)
            or in the next item (`-isysroot <dir>`, `--sysroot <dir>`).
        toolchain_sysroot: `cc_toolchain.sysroot`, which can be `None`.
        built_in_include_directories: `cc_toolchain.built_in_include_directories`.

    Returns:
        `["-isysroot", <SDK root>]`, or `[]` if clang already gets a usable
        sysroot from the flags or no SDK root is known.
    """
    isysroot = None
    sysroot = None
    pending = None  # the flag that takes the next item as its directory
    for flag in flags:
        if pending == "-isysroot":
            isysroot = flag
            pending = None
        elif pending == "--sysroot":
            sysroot = flag
            pending = None
        elif flag in ["-isysroot", "--sysroot"]:
            pending = flag
        elif flag.startswith("-isysroot"):
            isysroot = flag.removeprefix("-isysroot")
        elif flag.startswith("--sysroot="):
            sysroot = flag.removeprefix("--sysroot=")

    used_by_clang = sysroot if isysroot == None else isysroot
    if _is_usable(used_by_clang):
        return []

    # clang would use no sysroot, or a placeholder. A `--sysroot` next to a
    # placeholder `-isysroot` does not count: the build does not use it
    # either, because wrapped_clang makes the placeholder the Xcode SDK.
    sdk = toolchain_sysroot if _is_usable(toolchain_sysroot) else macos_sdk_root(built_in_include_directories)
    return ["-isysroot", sdk] if sdk else []

def macos_sdk_root(built_in_include_directories):
    """Return the macOS SDK root (a `<...>.sdk` path) of the built-in include dirs.

    Fallback for when `cc_toolchain.sysroot` is unset. clang-tidy runs as its
    own binary (often the hermetic one from toolchains_llvm), but its compiler
    flags come from whichever C++ toolchain is registered as the default. When
    none is registered, that's Bazel's auto-detected host toolchain
    (`@local_config_cc`). It leaves `builtin_sysroot` unset because the host
    clang self-resolves a default SDK. The SDK path still shows up in
    `built_in_include_directories` though (Bazel scrapes those from `clang -v`),
    so we recover the `.sdk` root from there.

    Uses `rfind` so an unrelated earlier `.sdk` path component (e.g. a user
    directory `/Users/foo.sdk/...`) can't mis-truncate the real SDK root.

    Args:
        built_in_include_directories: `cc_toolchain.built_in_include_directories`.

    Returns:
        The `.sdk` root path, or "" if no SDK dir is present.
    """
    for d in built_in_include_directories:
        idx = d.rfind(".sdk/")
        if idx != -1:
            return d[:idx + len(".sdk")]
    return ""
