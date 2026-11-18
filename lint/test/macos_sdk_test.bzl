"Unit tests: the sysroot that the clang-tidy aspect passes on macOS"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lint/private:macos_sdk.bzl", "macos_sdk_root", "macos_sysroot_args")

_SDK = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
_BUILT_IN = [
    "/Library/Developer/CommandLineTools/usr/lib/clang/17/include",
    _SDK + "/usr/include",
    _SDK + "/System/Library/Frameworks",
]

# What apple_support's toolchain passes.
_APPLE_SUPPORT = [
    "-isysroot",
    "__BAZEL_XCODE_SDKROOT__",
    "-F__BAZEL_XCODE_SDKROOT__/System/Library/Frameworks",
]

# The built-in include dirs of apple_support's toolchain. They name no SDK.
_APPLE_SUPPORT_BUILT_IN = [
    "/Applications/",
    "/Library/",
]

def _macos_sysroot_args_test_impl(ctx):
    env = unittest.begin(ctx)
    from_include_dirs = ["-isysroot", _SDK]

    # No sysroot in the flags: the toolchain's sysroot, else the SDK of its include dirs.
    asserts.equals(
        env,
        ["-isysroot", "/Toolchain/MacOSX.sdk"],
        macos_sysroot_args(["-O2"], "/Toolchain/MacOSX.sdk", _BUILT_IN),
    )
    asserts.equals(env, from_include_dirs, macos_sysroot_args(["-O2"], None, _BUILT_IN))
    asserts.equals(env, [], macos_sysroot_args(["-O2"], None, ["/usr/include"]))

    # A sysroot that the flags pin wins, in each spelling. The flags are one
    # list: it makes no difference if the toolchain, the command line or the
    # target gave the flag.
    for pinned in [
        ["-isysroot", "/Custom/MacOSX.sdk"],
        ["-isysroot/Custom/MacOSX.sdk"],
        ["--sysroot", "/Custom/MacOSX.sdk"],
        ["--sysroot=/Custom/MacOSX.sdk"],
    ]:
        # cc_toolchain.sysroot is not set. Without the pin, the SDK of the
        # include dirs would be added.
        asserts.equals(env, [], macos_sysroot_args(["-O2"] + pinned + ["-g"], None, _BUILT_IN))

        # cc_toolchain.sysroot is a different directory. The pin still wins.
        asserts.equals(env, [], macos_sysroot_args(pinned, "/Toolchain/MacOSX.sdk", _BUILT_IN))

    # The same sysroot as a flag and as cc_toolchain.sysroot, as a toolchain
    # with a `sysroot` feature gives it: nothing to add.
    asserts.equals(
        env,
        [],
        macos_sysroot_args(["--sysroot=/Toolchain/MacOSX.sdk"], "/Toolchain/MacOSX.sdk", _BUILT_IN),
    )

    # A sysroot flag without a directory pins nothing.
    asserts.equals(env, from_include_dirs, macos_sysroot_args(["-O2", "-isysroot"], None, _BUILT_IN))
    asserts.equals(env, from_include_dirs, macos_sysroot_args(["--sysroot"], None, _BUILT_IN))
    return unittest.end(env)

macos_sysroot_args_test = unittest.make(_macos_sysroot_args_test_impl)

def _apple_support_placeholder_test_impl(ctx):
    env = unittest.begin(ctx)
    from_include_dirs = ["-isysroot", _SDK]

    # The placeholder pins nothing. The SDK that the toolchain names is added.
    asserts.equals(env, from_include_dirs, macos_sysroot_args(_APPLE_SUPPORT, None, _BUILT_IN))
    asserts.equals(
        env,
        from_include_dirs,
        macos_sysroot_args(["-isysroot__BAZEL_XCODE_SDKROOT__"], None, _BUILT_IN),
    )

    # apple_support's own toolchain sets no sysroot, and its include dirs name
    # no SDK. There is nothing to add.
    asserts.equals(env, [], macos_sysroot_args(_APPLE_SUPPORT, None, _APPLE_SUPPORT_BUILT_IN))

    # A placeholder as cc_toolchain.sysroot is not usable either.
    asserts.equals(
        env,
        from_include_dirs,
        macos_sysroot_args(["-O2"], "__BAZEL_XCODE_SDKROOT__", _BUILT_IN),
    )

    # A later `-isysroot` wins over the placeholder, as it does in clang.
    asserts.equals(
        env,
        [],
        macos_sysroot_args(_APPLE_SUPPORT + ["-isysroot", "/Custom/MacOSX.sdk"], None, _BUILT_IN),
    )
    asserts.equals(
        env,
        [],
        macos_sysroot_args(_APPLE_SUPPORT + ["-isysroot/Custom/MacOSX.sdk"], None, _BUILT_IN),
    )

    # clang prefers the placeholder `-isysroot` to a `--sysroot`. So does the
    # build, where the placeholder becomes the Xcode SDK. The `--sysroot` pins
    # nothing.
    asserts.equals(
        env,
        from_include_dirs,
        macos_sysroot_args(_APPLE_SUPPORT + ["--sysroot=/Custom/MacOSX.sdk"], None, _BUILT_IN),
    )
    asserts.equals(
        env,
        from_include_dirs,
        macos_sysroot_args(["--sysroot", "/Custom/MacOSX.sdk"] + _APPLE_SUPPORT, None, _BUILT_IN),
    )
    asserts.equals(
        env,
        [],
        macos_sysroot_args(_APPLE_SUPPORT + ["--sysroot=/Custom/MacOSX.sdk"], None, _APPLE_SUPPORT_BUILT_IN),
    )
    return unittest.end(env)

apple_support_placeholder_test = unittest.make(_apple_support_placeholder_test_impl)

def _macos_sdk_root_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, _SDK, macos_sdk_root(_BUILT_IN))

    # The last `.sdk/` component is the SDK root.
    asserts.equals(
        env,
        "/Users/foo.sdk/SDKs/MacOSX.sdk",
        macos_sdk_root(["/Users/foo.sdk/SDKs/MacOSX.sdk/usr/include"]),
    )
    asserts.equals(env, "", macos_sdk_root(["/usr/include", "/usr/lib/clang/16/include"]))
    return unittest.end(env)

macos_sdk_root_test = unittest.make(_macos_sdk_root_test_impl)

def macos_sdk_test_suite(name):
    unittest.suite(
        name,
        macos_sysroot_args_test,
        apple_support_placeholder_test,
        macos_sdk_root_test,
    )
