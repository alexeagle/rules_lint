"""API for calling declaring a buf lint aspect.

Typical usage:

```
load("@aspect_rules_lint//lint:buf.bzl", "buf_lint_aspect")

buf = buf_lint_aspect(
    config = "@@//path/to:buf.yaml",
)
```
"""

load("@rules_proto//proto:defs.bzl", "ProtoInfo")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "report_files")

_MNEMONIC = "buf"

def _short_path(file, _):
    return file.path

def buf_lint_action(ctx, buf, protoc, target, stderr, exit_code = None):
    """Runs the buf lint tool as a Bazel action.

    Args:
        ctx: Rule OR Aspect context
        buf: the buf-lint executable
        protoc: the protoc executable
        target: the proto_library target to run on
        stderr: output file containing the stderr of protoc
        exit_code: output file to write the exit code.
            If None, then fail the build when protoc exits non-zero.
    """
    config = json.encode({
        "input_config": "" if ctx.file._config == None else ctx.file._config.short_path,
    })

    deps = depset(
        [target[ProtoInfo].direct_descriptor_set],
        transitive = [target[ProtoInfo].transitive_descriptor_sets],
    )

    sources = []
    source_files = []

    for f in target[ProtoInfo].direct_sources:
        source_files.append(f)

        # source is the argument passed to protoc. This is the import path "foo/foo.proto"
        # We have to trim the prefix if strip_import_prefix attr is used in proto_library.
        sources.append(
            f.path[len(target[ProtoInfo].proto_source_root) + 1:] if f.path.startswith(target[ProtoInfo].proto_source_root) else f.path,
        )

    args = ctx.actions.args()
    args.add_joined(["--plugin", "protoc-gen-buf-plugin", buf], join_with = "=")
    args.add_joined(["--buf-plugin_opt", config], join_with = "=")
    args.add_joined("--descriptor_set_in", deps, join_with = ":", map_each = _short_path)
    args.add_joined(["--buf-plugin_out", "."], join_with = "=")
    args.add_all(sources)
    outputs = [stderr]

    if exit_code:
        command = "{protoc} $@ 2>{stderr}; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        # Create empty file on success, as Bazel expects one
        command = "{protoc} $@ && touch {stderr}"

    ctx.actions.run_shell(
        inputs = depset([
            ctx.file._config,
            protoc,
            buf,
        ], transitive = [deps]),
        outputs = outputs,
        command = command.format(
            protoc = protoc.path,
            stderr = stderr.path,
        ),
        arguments = [args],
        mnemonic = _MNEMONIC,
    )

def _buf_lint_aspect_impl(target, ctx):
    if ctx.rule.kind not in ["proto_library"]:
        return []

    report, exit_code, info = report_files(_MNEMONIC, target, ctx)
    buf_lint_action(
        ctx,
        ctx.toolchains[ctx.attr._buf_toolchain].cli,
        ctx.toolchains["@rules_proto//proto:toolchain_type"].proto.proto_compiler.executable,
        target,
        report,
        exit_code,
    )
    return [info]

def lint_buf_aspect(config, toolchain = "@rules_buf//tools/protoc-gen-buf-lint:toolchain_type"):
    """A factory function to create a linter aspect.

    Args:
        config: label of the the buf.yaml file
        toolchain: override the default toolchain of the protoc-gen-buf-lint tool
    """
    return aspect(
        implementation = _buf_lint_aspect_impl,
        attr_aspects = ["deps"],
        attrs = {
            "_options": attr.label(
                default = "//lint:fail_on_violation",
                providers = [LintOptionsInfo],
            ),
            "_buf_toolchain": attr.string(
                default = toolchain,
            ),
            "_config": attr.label(
                default = config,
                allow_single_file = True,
            ),
        },
        toolchains = [toolchain, "@rules_proto//proto:toolchain_type"],
    )
