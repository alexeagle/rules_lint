"Patcher binary that includes diff tool"

load("@aspect_rules_js//js:defs.bzl", "js_binary")

_DIFF_TOOLCHAIN = "@diff.bzl//diff/toolchain:execution_type"

def _diff_bin_impl(ctx):
    diff_bin = ctx.toolchains[_DIFF_TOOLCHAIN].diffutilsinfo.diff_bin
    # Use basename to maintain .exe file extension on windows to allow for execution
    diff_copy = ctx.actions.declare_file(diff_bin.basename)
    ctx.actions.symlink(output = diff_copy, target_file = diff_bin, is_executable = True)
    return DefaultInfo(
        files = depset([diff_copy]),
        runfiles = ctx.runfiles(files = [diff_copy]),
    )

_diff_bin = rule(
    doc = "Copies the diff binary out of the resolved toolchain, preserving its filename.",
    implementation = _diff_bin_impl,
    toolchains = [_DIFF_TOOLCHAIN],
)

def patcher_binary(name):
    """Create a js_binary that can be used to run the patcher.mjs script.

    Args:
        name: The name of the patcher binary.
    """
    diff_bin = "_{}.diff_bin".format(name)
    _diff_bin(name = diff_bin)

    js_binary(
        name = name,
        data = [diff_bin],
        entry_point = "patcher.mjs",
        env = {"DIFF_BIN": "$(rlocationpath {})".format(diff_bin)},
        log_level = select({
            "@rules_lint//lint:debug.enabled": "debug",
            "//conditions:default": "error",
        }),
        # Because aspect visibility rules are not on by default.
        visibility = ["//visibility:public"],
    )
