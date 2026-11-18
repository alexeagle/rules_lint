"Unit test for with_gcc_builtin_includes_last"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//lint/private:gcc_includes.bzl", "with_gcc_builtin_includes_last")

_GCC = "external/gcc_toolchain_x86_64/lib/gcc/x86_64-linux/15.2.0"

def _gcc_includes_test_impl(ctx):
    env = unittest.begin(ctx)
    for gcc_include in [
        ["-isystem" + _GCC + "/include"],
        ["-isystem", _GCC + "/include"],
        ["-idirafter" + _GCC + "/include"],
        ["-idirafter", _GCC + "/include"],
    ]:
        asserts.equals(
            env,
            ["-nostdlibinc", "-nostdinc++", "-isystem" + _GCC + "/include-fixed", "-isystemexternal/sysroot/usr/include", "-idirafter" + _GCC + "/include"],
            with_gcc_builtin_includes_last(["-nostdinc", "-nostdinc++"] + gcc_include + ["-isystem" + _GCC + "/include-fixed", "-isystemexternal/sysroot/usr/include"]),
        )
    asserts.equals(env, ["-idirafter" + _GCC + "/include"], with_gcc_builtin_includes_last(["-isystem" + _GCC + "/include"]))
    for unchanged in [
        ["-nostdinc", "-isystem", "external/llvm_toolchain_llvm/lib/clang/16/include"],
        ["-nostdinc", "-isystem" + _GCC + "/include-fixed", "-isystem" + _GCC + "/plugin/include"],
    ]:
        asserts.equals(env, unchanged, with_gcc_builtin_includes_last(unchanged))
    return unittest.end(env)

gcc_includes_test = unittest.make(_gcc_includes_test_impl)
