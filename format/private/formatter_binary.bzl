"Implementation of formatter_binary"

load("@aspect_bazel_lib//lib:paths.bzl", "BASH_RLOCATION_FUNCTION", "to_rlocation_path")

# Per the formatter design, each language can only have a single formatter binary
TOOLS = {
    "javascript": "prettier",
    "markdown": "prettier-md",
    "python": "ruff",
    "starlark": "buildifier",
    "jsonnet": "jsonnetfmt",
    "terraform": "terraform-fmt",
    "kotlin": "ktfmt",
    "java": "java-format",
    "scala": "scalafmt",
    "swift": "swiftformat",
    "go": "gofmt",
    "sql": "prettier-sql",
    "sh": "shfmt",
    "protocol_buffer": "buf",
    "cc": "clang-format",
    "yaml": "yamlfmt",
}

def _formatter_binary_impl(ctx):
    substitutions = {}
    tools = {v: getattr(ctx.attr, k) for k, v in TOOLS.items()}
    for tool, attr in tools.items():
        if attr:
            substitutions["{{%s}}" % tool] = to_rlocation_path(ctx, attr.files_to_run.executable)
    if len(substitutions) == 0:
        fail("format_multirun should have at least one language attribute set to a formatter tool")

    substitutions.update({
        # We need to fill in the rlocation paths in the shell script
        "{{BASH_RLOCATION_FUNCTION}}": BASH_RLOCATION_FUNCTION,
        # Support helpful error reporting
        "{{fix_target}}": str(ctx.label),
    })

    # Uniquely named output file allowing more than one formatter in a package
    bin = ctx.actions.declare_file("_{}.fmt.sh".format(ctx.label.name))
    ctx.actions.expand_template(
        template = ctx.file._bin,
        output = bin,
        substitutions = substitutions,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [ctx.file._runfiles_lib] + [
        f.files_to_run.executable
        for f in tools.values()
        if f
    ] + [
        f.files_to_run.runfiles_manifest
        for f in tools.values()
        if f and f.files_to_run.runfiles_manifest
    ])
    runfiles = runfiles.merge_all([
        f.default_runfiles
        for f in tools.values()
        if f
    ])

    return [
        DefaultInfo(
            executable = bin,
            runfiles = runfiles,
        ),
    ]

formatter_binary_lib = struct(
    implementation = _formatter_binary_impl,
    attrs = dict({
        k: attr.label(doc = "a binary target that runs {} (or another tool with compatible CLI arguments)".format(v), executable = True, cfg = "exec", allow_files = True)
        for k, v in TOOLS.items()
    }, **{
        "_bin": attr.label(default = "//format/private:format.sh", allow_single_file = True),
        "_runfiles_lib": attr.label(default = "@bazel_tools//tools/bash/runfiles", allow_single_file = True),
    }),
)

format_multirun = rule(
    doc = "Produces an executable that aggregates the supplied formatter binaries",
    implementation = formatter_binary_lib.implementation,
    attrs = formatter_binary_lib.attrs,
    executable = True,
)
