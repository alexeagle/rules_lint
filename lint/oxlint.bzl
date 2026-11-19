"""Configures [Oxlint](https://oxc.rs/docs/guide/usage/linter.html) to run as a Bazel aspect.

First, add `oxlint` to your npm dependencies and declare its binary, typically in
`tools/lint/BUILD.bazel`:

```starlark
load("@npm//:oxlint/package_json.bzl", oxlint_bin = "bin")

oxlint_bin.oxlint_binary(name = "oxlint")
```

The npm distribution is required when your configuration loads
[JavaScript plugins](https://oxc.rs/docs/guide/usage/linter/js-plugins), including
custom plugins you write, because they require a JavaScript runtime.

Then declare the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:oxlint.bzl", "lint_oxlint_aspect")

oxlint = lint_oxlint_aspect(
    binary = Label("//tools/lint:oxlint"),
    config = Label("//:.oxlintrc.json"),
)
```

For configs that import other files or load JS plugins, use a `js_library` with
one config source and dependencies on its imported configs, plugins, and package
metadata. Set `config` to that library. Its transitive JsInfo inputs are included
in the action, alongside the linted target's dependencies, data, and tsconfig.
Additional input targets can be supplied through `config_deps`.

```starlark
js_library(
    name = "oxlint_config",
    srcs = ["oxlint.config.ts"],
    deps = [":shared_config", ":node_modules/my-plugin"],
)
```

Type-aware linting is opt-in: install a compatible `oxlint-tsgolint`, declare its
`bin.tsgolint_binary`, and pass `type_aware = True` and `tsgolint = Label(...)` to
`lint_oxlint_aspect`. The target's tsconfig (including its `ts_config` dependencies)
and dependency declarations are included automatically. Use `config_deps` for
project metadata or type packages not present in the target's own dependencies.
The backend runs in the execution configuration, including its runfiles.
It discovers `tsconfig.json` beside or above source files. Non-standard config
names are currently unsupported by the backend, even with `--tsconfig`:
https://github.com/oxc-project/oxc/issues/20328.

Fixes run until source contents stabilize, with cycle detection and a ten-pass
limit. Original-source diagnostics still determine the lint result. When fixing
JS configs/plugins, declare a second Oxlint binary with `patch_node_fs = False`
and pass it as `fix_binary`. The patcher intentionally symlinks dependencies into
a writable shadow tree; rules_js filesystem patching rejects those links.
"""

load("@aspect_rules_js//js:libs.bzl", "js_lib_helpers")
load("@aspect_rules_js//js:providers.bzl", "JsInfo")
load("@bazel_lib//lib:paths.bzl", "relative_file")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("//lint/private:js_linter_inputs.bzl", "COPY_FILE_TO_BIN_TOOLCHAINS", "copy_or_reuse_bin_inputs")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "patch_and_output_files", "should_visit")
load("//lint/private:patcher_action.bzl", "patcher_attrs", "run_patcher")

_MNEMONIC = "AspectRulesLintOxlint"

def _gather_inputs(ctx, target, srcs, config):
    dependencies = [ctx.attr._config_file] + ctx.attr._config_deps + getattr(ctx.rule.attr, "deps", [])
    for name in ["tsconfig", "extends", "package_json"]:
        dependency = getattr(ctx.rule.attr, name, None)
        if dependency != None:
            dependencies.extend(dependency if type(dependency) == "list" else [dependency])
    dependencies.extend(getattr(ctx.rule.attr, "data", []))

    files = [config]
    for dependency in dependencies:
        if JsInfo not in dependency:
            files.extend(dependency.files.to_list())
    if "gather_files_from_js_providers" in dir(js_lib_helpers):
        # rules_js 1.x
        js_files = js_lib_helpers.gather_files_from_js_providers(
            dependencies,
            include_transitive_sources = True,
            include_declarations = True,
            include_npm_linked_packages = True,
        )
    else:
        # rules_js 2.x
        js_files = js_lib_helpers.gather_files_from_js_infos(
            dependencies,
            include_sources = True,
            include_transitive_sources = True,
            include_types = True,
            include_transitive_types = True,
            include_npm_sources = True,
        )
    files.extend(js_files.to_list())

    # JS rules own copies in their packages. An aspect cannot copy a config
    # from another package; standalone raw JSON configs can still be read from
    # the execroot. Prefer the bin mirror when the config supplies JsInfo.
    bin_files = {file.short_path: file for file in files if not file.is_source}

    # Plain tsconfig/data files owned by the linted package also need mirrors
    # beside the copied sources for TypeScript's config discovery.
    local_files = [
        file
        for file in files
        if file.is_source and file.short_path not in bin_files and
           file.owner.package == ctx.label.package and
           file.owner.workspace_name == ctx.label.workspace_name
    ]
    copied = copy_or_reuse_bin_inputs(ctx, target, depset(srcs + local_files).to_list())
    bin_files.update({file.short_path: file for file in copied})
    return depset(copied + [bin_files.get(file.short_path, file) for file in files]).to_list()

def _bin_relative(ctx, file):
    return relative_file(to_file = file.path, frm_file = ctx.bin_dir.path + "/_oxlint_anchor")

def oxlint_action(ctx, executable, srcs, config, stdout, exit_code = None, args = [], format = None, patch = None, target = None):
    """Run Oxlint as a Bazel action.

    Args:
        ctx: Bazel rule or aspect evaluation context
        executable: the Oxlint executable
        srcs: JavaScript or TypeScript files to lint
        config: Oxlint configuration file
        stdout: output file for diagnostics
        exit_code: optional output file for the exit code; without it, violations fail the action
        args: additional Oxlint command-line arguments
        format: optional Oxlint output format
        patch: optional output patch; when present, run Oxlint with `--fix`
        target: aspect target, used to reuse existing bin-tree copies
    """
    inputs = _gather_inputs(ctx, target, srcs, config)
    bin_files = {file.short_path: file for file in inputs}
    action_args = ctx.actions.args()
    action_args.add_all(args)
    action_args.add_all(["--config", _bin_relative(ctx, bin_files[config.short_path])])
    if ctx.attr._type_aware:
        action_args.add("--type-aware")
    if format:
        action_args.add_all(["--format", format])
    if patch:
        action_args.add("--fix")
    action_args.add_all([_bin_relative(ctx, bin_files[src.short_path]) for src in srcs])

    env = dict(ctx.attr._env, BAZEL_BINDIR = ctx.bin_dir.path)
    tools = [executable]
    if ctx.attr._type_aware:
        env["OXLINT_TSGOLINT_PATH"] = _bin_relative(ctx, ctx.executable._tsgolint)
        tools.append(ctx.attr._tsgolint[DefaultInfo].files_to_run)
    if patch:
        run_patcher(
            ctx,
            ctx.executable,
            inputs = inputs,
            args = action_args,
            files_to_diff = [src.short_path for src in srcs],
            patch_out = patch,
            patch_cfg_env = env,
            tools = tools,
            patch_cfg_suffix = ctx.attr._mnemonic + ".patch_cfg",
            max_fix_passes = 10,
            chdir = ctx.bin_dir.path,
            exit_code = exit_code,
            mnemonic = ctx.attr._mnemonic,
            progress_message = "Fixing %{label} with Oxlint",
        )
        return

    outputs = [stdout]
    if exit_code:
        command = '"$execroot"/{oxlint} "$@" >"$execroot"/{stdout} 2>&1; echo $? >"$execroot"/{exit_code}'
        outputs.append(exit_code)
    else:
        command = '"$execroot"/{oxlint} "$@" >"$execroot"/{stdout} 2>&1'

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        arguments = [action_args],
        # Set cwd explicitly so native binaries and rules_js launchers resolve
        # the same bin-relative paths. Keep reports relative to the execroot.
        command = 'execroot="$PWD"; cd {} && '.format(shell.quote(ctx.bin_dir.path)) + command.format(
            oxlint = shell.quote(executable.path),
            stdout = shell.quote(stdout.path),
            exit_code = shell.quote(exit_code.path) if exit_code else "",
        ),
        env = env,
        tools = tools,
        mnemonic = ctx.attr._mnemonic,
        progress_message = "Linting %{label} with Oxlint",
    )

# buildifier: disable=function-docstring
def _oxlint_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds, ctx.attr._filegroup_tags):
        return []

    files_to_lint = filter_srcs(ctx.rule)
    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(ctx.attr._mnemonic, target, ctx)
    else:
        outputs, info = output_files(ctx.attr._mnemonic, target, ctx)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    # Always report the original violations. Fixes are produced by a separate action so
    # `aspect lint` still exits non-zero when it offers an unapplied patch.
    oxlint_action(
        ctx,
        ctx.executable._oxlint,
        files_to_lint,
        ctx.file._config_file,
        outputs.human.out,
        outputs.human.exit_code,
        args = ctx.attr._args,
        target = target,
    )

    if ctx.attr._options[LintOptionsInfo].fix:
        patch_exit_code = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = ctx.attr._mnemonic, suffix = "patch.exit_code"))
        oxlint_action(
            ctx,
            ctx.executable._oxlint_for_fix,
            files_to_lint,
            ctx.file._config_file,
            None,
            patch_exit_code,
            args = ctx.attr._args,
            target = target,
            patch = outputs.patch,
        )

    # Oxlint emits SARIF natively, so no rules_lint parser action is needed.
    oxlint_action(
        ctx,
        ctx.executable._oxlint,
        files_to_lint,
        ctx.file._config_file,
        outputs.machine.out,
        outputs.machine.exit_code,
        args = ctx.attr._args,
        target = target,
        format = "sarif",
    )

    return [info]

def lint_oxlint_aspect(
        binary,
        config,
        rule_kinds = ["js_library", "ts_project", "ts_project_rule"],
        filegroup_tags = ["lint-with-oxlint"],
        args = [],
        config_deps = [],
        type_aware = False,
        tsgolint = None,
        env = {},
        fix_binary = None,
        mnemonic = _MNEMONIC):
    """Create an Oxlint aspect.

    Args:
        binary: an Oxlint executable
        config: an Oxlint configuration file
        rule_kinds: target kinds visited automatically
        filegroup_tags: tags that opt filegroups into Oxlint
        args: additional Oxlint command-line arguments
        config_deps: labels supplying imported configs, plugins, package metadata, or extra type inputs
        type_aware: enable type-aware rules (requires tsgolint)
        tsgolint: executable for the compatible oxlint-tsgolint backend
        env: additional environment variables for Oxlint
        fix_binary: optional Oxlint executable for fixes; use a rules_js binary with
            patch_node_fs = False when JS configs/plugins follow shadow-tree symlinks
        mnemonic: unique output name when multiple Oxlint configurations visit the same target
    """
    if type_aware and tsgolint == None:
        fail("type_aware requires a tsgolint executable")
    return aspect(
        implementation = _oxlint_aspect_impl,
        attrs = patcher_attrs | ({
            "_tsgolint": attr.label(default = tsgolint, executable = True, cfg = "exec"),
        } if type_aware else {}) | {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_oxlint": attr.label(
                default = binary,
                allow_files = True,
                executable = True,
                cfg = "exec",
            ),
            "_oxlint_for_fix": attr.label(
                default = fix_binary if fix_binary != None else binary,
                allow_files = True,
                executable = True,
                cfg = "exec",
            ),
            "_config_deps": attr.label_list(default = config_deps, allow_files = True),
            "_type_aware": attr.bool(default = type_aware),
            "_mnemonic": attr.string(default = mnemonic),
            "_env": attr.string_dict(default = env),
            "_config_file": attr.label(
                default = config,
                allow_single_file = True,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
            "_filegroup_tags": attr.string_list(
                default = filegroup_tags,
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
        toolchains = COPY_FILE_TO_BIN_TOOLCHAINS,
    )
