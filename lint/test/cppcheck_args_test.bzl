"""Check deferred cppcheck arguments, including both report formats."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//lint:cppcheck.bzl", "cppcheck_action")

def _fixture_impl(ctx):
    compilation_context = struct(
        headers = depset(),
        framework_includes = depset(["framework dir"]),
        includes = depset(["include dir", "shared"], transitive = [depset(["transitive"])]),
        quote_includes = depset(["quote dir", "shared"]),
        system_includes = depset(["system dir"]),
        external_includes = depset(["external dir"]),
    )
    for xml in [False, True]:
        suffix = "xml" if xml else "text"
        cppcheck_action(
            ctx,
            compilation_context,
            ctx.executable,
            ctx.files.srcs,
            ctx.actions.declare_file(ctx.label.name + "." + suffix),
            ctx.actions.declare_file(ctx.label.name + "." + suffix + ".exit_code"),
            do_xml = xml,
            args = ["--custom=with space"],
        )
    return []

_fixture = rule(
    implementation = _fixture_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "_cppcheck": attr.label(default = "//lint:cppcheck_wrapper", executable = True, cfg = "exec"),
        "_cppcheck_wrapper": attr.label(default = "//lint:cppcheck_wrapper", executable = True, cfg = "exec"),
        "_verbose": attr.bool(),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)

def _args_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    asserts.equals(env, 2, len(actions))
    for action in actions:
        xml = "CPPCHECK__OUTPUT_FILE" in action.env
        expected = [
            "--custom=with space",
            "--error-exitcode=31",
            "-Iframework dir",
            "-Itransitive",
            "-Iinclude dir",
            "-Ishared",
            "-Iquote dir",
            "-Ishared",
            "-Isystem dir",
            "-Iexternal dir",
            "--xml-version=3" if xml else "--template={file}:{line}:{column}: {severity}: {message} [{severity} {id}]",
            "lint/test/clang_tidy_wrapper_test.sh",
        ]
        asserts.equals(env, expected, action.argv[-len(expected):])
    return analysistest.end(env)

_args_test = analysistest.make(_args_test_impl)

def cppcheck_args_test_suite(name):
    _fixture(
        name = name + "_fixture",
        srcs = ["clang_tidy_wrapper_test.sh"],
        tags = ["manual"],
    )
    _args_test(
        name = name,
        target_under_test = ":" + name + "_fixture",
    )
