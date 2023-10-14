"Implementation of formatter_binary"

load("@aspect_bazel_lib//lib:paths.bzl", "to_rlocation_path")

_attrs = {
    "formatters": attr.label_keyed_string_dict(mandatory = True),
    "_bin": attr.label(default = "//format/private:format.sh", allow_single_file = True),
    "_runfiles_lib": attr.label(default = "@bazel_tools//tools/bash/runfiles", allow_single_file = True),
}

def _formatter_binary_impl(ctx):
    # We need to fill in the rlocation paths in the shell script
    substitutions = {}
    for formatter, lang in ctx.attr.formatters.items():
        if lang == "python":
            substitutions["{{black}}"] = to_rlocation_path(ctx, formatter.files_to_run.executable)
        else:
            fail("lang {} not recognized".format(lang))

    bin = ctx.actions.declare_file("format.sh")
    ctx.actions.expand_template(
        template = ctx.file._bin,
        output = bin,
        substitutions = substitutions,
        is_executable = True,
    )
    runfiles = ctx.runfiles(
        [ctx.file._runfiles_lib],
    ).merge_all(
        [f.default_runfiles for f in ctx.attr.formatters.keys()],
    )

    return [
        DefaultInfo(
            executable = bin,
            runfiles = runfiles,
        ),
    ]

formatter_binary_lib = struct(
    implementation = _formatter_binary_impl,
    attrs = _attrs,
)
