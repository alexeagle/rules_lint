load("@rules_lint//lint/private:patcher_action.bzl", "patcher_attrs", _run_patcher = "run_patcher")
load("@bazel_lib//lib:expand_make_vars.bzl", _expand_locations = "expand_locations")

# TODO: Remove this file after rules_lint includes this patcher_run fix and lint/rust/MODULE.bazel requires that release.

def _repository_relative_path(file):
    if not file.short_path.startswith("../"):
        return file.short_path

    components = file.short_path.split("/")
    if len(components) < 3:
        fail("{} does not contain a repository-relative path".format(file.short_path))
    return "/".join(components[2:])

def _workspace_root(file, repository_relative_path):
    if file.path == repository_relative_path:
        return "."

    suffix = "/" + repository_relative_path
    if not file.path.endswith(suffix):
        fail("{} does not end with {}".format(file.path, repository_relative_path))
    return file.path[:-len(suffix)]

def _patcher_run_impl(ctx):
    diff_file = ctx.actions.declare_file("_{}.diff".format(ctx.label.name))

    files_to_diff = ctx.files.files_to_diff
    if not files_to_diff:
        fail("files_to_diff must not be empty")

    files_to_diff_paths = [
        _repository_relative_path(f)
        for f in files_to_diff
    ]
    workspace_root = _workspace_root(files_to_diff[0], files_to_diff_paths[0])
    for i in range(1, len(files_to_diff)):
        current_workspace_root = _workspace_root(files_to_diff[i], files_to_diff_paths[i])
        if current_workspace_root != workspace_root:
            fail("files_to_diff must belong to one repository")

    data = ctx.files.data
    env = ctx.attr.env
    inputs = [
        ctx.executable.tool,
    ] + files_to_diff + data
    tool_args = [
        _expand_locations(ctx, arg, ctx.attr.data)
        for arg in ctx.attr.tool_args
    ]

    _run_patcher(
        ctx,
        ctx.executable,
        inputs = inputs,
        args = tool_args,
        files_to_diff = files_to_diff_paths,
        patch_out = diff_file,
        tools = [ctx.executable.tool],
        patch_cfg_env = dict(env, **{"BAZEL_BINDIR": workspace_root}),
        env = env,
        mnemonic = ctx.attr.mnemonic,
        progress_message = "Running patcher in %{label} as part of the build",
    )

    return [DefaultInfo(files = depset([diff_file]))]

patcher_run = rule(
    doc = "A rule that wraps patcher_action to make running tests easier.",
    implementation = _patcher_run_impl,
    attrs = patcher_attrs | {
        "tool": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
        ),
        "files_to_diff": attr.label_list(
            mandatory = True,
            allow_files = True,
        ),
        "mnemonic": attr.string(
            default = "Patcher",
        ),
        "tool_args": attr.string_list(
            default = [],
        ),
        "data": attr.label_list(
            default = [],
            allow_files = True,
        ),
        "env": attr.string_dict(
            default = {},
        ),
    },
)
