"Unit tests: the flags that the clang-tidy aspect takes from the C/C++ toolchain"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lint/private:clang_tidy_flags.bzl", "update_flag")

def _update_flags(flags, msvc):
    updated = []
    for flag in flags:
        updated.extend(update_flag(flag, msvc))
    return updated

def _absolute_paths_test_impl(ctx):
    env = unittest.begin(ctx)

    # Without an MSVC toolchain, an item that starts with `/` is a path. It
    # stays with the flag before it, also when it starts like an MSVC option
    # (`/D`, `/I`, `/W`, `/external`).
    flags = [
        "-isystem",
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/c++/v1",
        "-isysroot",
        "/Developer/SDKs/MacOSX.sdk",
        "-I",
        "/Imports/include",
        "-include",
        "/Workspace/config.h",
        "-iquote",
        "/external/dep",
        "-std=c++17",
    ]
    asserts.equals(env, flags, _update_flags(flags, msvc = False))

    # The other filters still apply: GCC-only options and every `-W` option
    # are dropped.
    asserts.equals(
        env,
        ["-O2"],
        _update_flags(["-fno-canonical-system-headers", "-Wall", "-O2", "-fstack-usage"], msvc = False),
    )
    return unittest.end(env)

absolute_paths_test = unittest.make(_absolute_paths_test_impl)

def _msvc_options_test_impl(ctx):
    env = unittest.begin(ctx)

    # With an MSVC toolchain, the options are translated or dropped as before.
    asserts.equals(
        env,
        ["-std=c++20", "-DNDEBUG", "-include", "pch.h", "-iquote", "include", "-D_MT"],
        _update_flags(
            [
                "/nologo",
                "/std:c++20",
                "/DNDEBUG",
                "/FIpch.h",
                "/Iinclude",
                "/MD",
                "/W4",
                "/wd4117",
                "/Zi",
                "/showIncludes",
                "/external:W0",
            ],
            msvc = True,
        ),
    )

    # An item that starts with `/` is still an option there, not a path.
    asserts.equals(env, ["-isystem"], _update_flags(["-isystem", "/abs/include"], msvc = True))
    return unittest.end(env)

msvc_options_test = unittest.make(_msvc_options_test_impl)

def clang_tidy_flags_test_suite(name):
    unittest.suite(
        name,
        absolute_paths_test,
        msvc_options_test,
    )
