"""API for calling declaring an ESLint lint aspect.

Typical usage:

First, install eslint using your typical npm package.json and rules_js rules.

Next, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
load("@npm//:eslint/package_json.bzl", eslint_bin = "bin")
eslint_bin.eslint_binary(name = "eslint")
```

Finally, create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:eslint.bzl", "lint_eslint_aspect")

eslint = lint_eslint_aspect(
    binary = Label("//tools/lint:eslint"),
    # We trust that eslint will locate the correct configuration file for a given source file.
    # See https://eslint.org/docs/latest/use/configure/configuration-files#cascading-and-hierarchy
    configs = [
        Label("//:eslintrc"),
        ...
    ],
)
```

### With ts_project prior to version 3.2.0

Prior to [commit 5e25e91](https://github.com/aspect-build/rules_ts/commit/5e25e91420947e3a81938d8eb076803e5cf51fe2)
the rule produced by the `ts_project` macro and a custom `transpiler` expanded the macro to
multiple targets, including changing the default target to `js_library`.

Since you want to lint the original TypeScript source files, the `ts_project` rule produced
by the macro is the one you want to lint, so when used with an `eslint_test` you should use
the `[name]_typings` label:

```
ts_project(
    name = "my_ts",
    transpiler = swc,
    ...
)

eslint_test(
    name = "lint_my_ts",
    srcs = [":my_ts_typings"],
)
```

See the [react example](https://github.com/bazelbuild/examples/blob/b498bb106b2028b531ceffbd10cc89530814a177/frontend/react/src/BUILD.bazel#L86-L92)
"""

load("@aspect_rules_js//js:libs.bzl", "js_lib_helpers")
load("//lint/private:js_linter_inputs.bzl", "COPY_FILE_TO_BIN_TOOLCHAINS", "copy_or_reuse_bin_inputs")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "patch_and_output_files", "should_visit")
load("//lint/private:patcher_action.bzl", "patcher_attrs", "run_patcher")

_MNEMONIC = "AspectRulesLintESLint"

def _gather_inputs(ctx, target, srcs, files):
    inputs = copy_or_reuse_bin_inputs(ctx, target, srcs)

    js_inputs = ctx.attr._config_files + getattr(ctx.rule.attr, "deps", []) + files

    # Linting of ts targets often requires the tsconfig
    if hasattr(ctx.rule.attr, "tsconfig"):
        js_inputs.append(ctx.rule.attr.tsconfig)

    # Add the config file along with any deps it has on npm packages
    if "gather_files_from_js_providers" in dir(js_lib_helpers):
        # rules_js 1.x
        js_inputs = js_lib_helpers.gather_files_from_js_providers(
            js_inputs,
            include_transitive_sources = True,
            include_declarations = True,
            include_npm_linked_packages = True,
        )
    else:
        # rules_js 2.x
        js_inputs = js_lib_helpers.gather_files_from_js_infos(
            js_inputs,
            include_sources = True,
            include_transitive_sources = True,
            include_types = True,
            include_transitive_types = True,
            include_npm_sources = True,
        )
    return depset(inputs, transitive = [js_inputs])

def eslint_action(ctx, executable, srcs, stdout, exit_code = None, format = "stylish", env = {}, patch = None, target = None, args = []):
    """Create a Bazel Action that spawns an eslint process.

    Adapter for wrapping Bazel around
    https://eslint.org/docs/latest/use/command-line-interface

    Args:
        ctx: an action context OR aspect context
        executable: struct with an eslint field
        srcs: list of file objects to lint
        stdout: output file containing the stdout or --output-file of eslint
        exit_code: output file containing the exit code of eslint.
            If None, then fail the build when eslint exits non-zero.
        format: value for eslint `--format` CLI flag
        env: environment variables for eslint
        patch: output file for patch (optional). If provided, uses run_patcher instead of run/run_shell.
        target: the aspect target, used to reuse bin-tree inputs already produced by the target
        args: additional command-line arguments to pass to eslint
    """
    file_inputs = [ctx.attr._workaround_17660]

    if patch != None:
        # Use run_patcher for fix mode
        # Build args list efficiently for JSON encoding (run_patcher needs a list)
        if type(format) == "string":
            format_args = [format]
        else:
            format_args = ["../../../" + format.files.to_list()[0].path]
            file_inputs.append(format)
        args_list = (
            args +
            ["--fix"] +
            (["--debug"] if ctx.attr._options[LintOptionsInfo].debug else []) +
            ["--format"] + format_args +
            [s.short_path for s in srcs]
        )

        run_patcher(
            ctx,
            executable,
            inputs = _gather_inputs(ctx, target, srcs, file_inputs),
            args = args_list,
            files_to_diff = [s.path for s in srcs],
            patch_out = patch,
            tools = [executable._eslint],
            patch_cfg_env = dict(env, **{"BAZEL_BINDIR": ctx.bin_dir.path}),
            stdout = stdout,
            exit_code = exit_code,
            env = env,
            mnemonic = _MNEMONIC,
            progress_message = "Linting %{label} with ESLint",
        )
    else:
        # Use run/run_shell for lint mode
        action_args = ctx.actions.args()
        action_args.add_all(args)
        action_args.add("--no-warn-ignored")
        if ctx.attr._options[LintOptionsInfo].debug:
            action_args.add("--debug")
        if type(format) == "string":
            action_args.add_all(["--format", format])
        else:
            action_args.add_all(["--format", "../../../" + format.files.to_list()[0].path])
            file_inputs.append(format)
        action_args.add_all([s.short_path for s in srcs])

        if not exit_code:
            ctx.actions.run_shell(
                inputs = _gather_inputs(ctx, target, srcs, file_inputs),
                outputs = [stdout],
                tools = [executable._eslint],
                arguments = [action_args],
                command = executable._eslint.path + " $@ && touch " + stdout.path,
                env = dict(env, **{
                    "BAZEL_BINDIR": ctx.bin_dir.path,
                }),
                mnemonic = _MNEMONIC,
                progress_message = "Linting %{label} with ESLint",
            )
        else:
            # Workaround: create an empty file in case eslint doesn't write one
            # Use `../../..` to return to the execroot?
            action_args.add_joined(["--node_options", "--require", "../../../" + ctx.file._workaround_17660.path], join_with = "=")

            action_args.add_all(["--output-file", stdout.short_path])

            ctx.actions.run(
                inputs = _gather_inputs(ctx, target, srcs, file_inputs),
                outputs = [stdout, exit_code],
                executable = executable._eslint,
                arguments = [action_args],
                env = env | {"BAZEL_BINDIR": ctx.bin_dir.path} | {"JS_BINARY__EXIT_CODE_OUTPUT_FILE": exit_code.path} if exit_code else {},
                mnemonic = _MNEMONIC,
                progress_message = "Linting %{label} with ESLint",
            )

# buildifier: disable=function-docstring
def _eslint_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    files_to_lint = filter_srcs(ctx.rule)
    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(_MNEMONIC, target, ctx)
    else:
        outputs, info = output_files(_MNEMONIC, target, ctx)

    # https://www.npmjs.com/package/chalk#chalklevel
    # 2: Force 256 color support even when a tty isn't detected
    color_env = {"FORCE_COLOR": "2"} if ctx.attr._options[LintOptionsInfo].color else {}

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    eslint_action(
        ctx,
        ctx.executable,
        files_to_lint,
        outputs.human.out,
        outputs.human.exit_code,
        format = ctx.attr._stylish_formatter,
        env = color_env,
        patch = getattr(outputs, "patch", None),
        target = target,
        args = ctx.attr._args,
    )

    # TODO(alex): if we run with --fix, this will report the issues that were fixed. Does a machine reader want to know about them?
    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    eslint_action(ctx, ctx.executable, files_to_lint, raw_machine_report, outputs.machine.exit_code, format = ctx.attr._compact_formatter, target = target, args = ctx.attr._args)

    # We could probably use https://www.npmjs.com/package/@microsoft/eslint-formatter-sarif instead.
    # However it probably requires the user to install this and pass it to us.
    # Also we always have the problem of getting execroot-relative paths
    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)

    return [info]

def lint_eslint_aspect(binary, configs, rule_kinds = ["js_library", "ts_project", "ts_project_rule"], args = []):
    """A factory function to create a linter aspect.

    Args:
        binary: the eslint binary, typically a rule like

            ```
            load("@npm//:eslint/package_json.bzl", eslint_bin = "bin")
            eslint_bin.eslint_binary(name = "eslint")
            ```
        configs: label(s) of the eslint config file(s)
        rule_kinds: which [kinds](https://bazel.build/query/language#kind) of rules should be visited by the aspect
        args: additional command-line arguments to pass to eslint
    """

    # syntax-sugar: allow a single config file in addition to a list
    if type(configs) == "string":
        configs = [configs]
    return aspect(
        implementation = _eslint_aspect_impl,
        attrs = patcher_attrs | {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_eslint": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_config_files": attr.label_list(
                default = configs,
                allow_files = True,
            ),
            "_workaround_17660": attr.label(
                default = "@rules_lint//lint/js:eslint.workaround_17660",
                allow_single_file = True,
                cfg = "exec",
            ),
            "_compact_formatter": attr.label(
                default = "@rules_lint//lint/js:eslint.compact-formatter",
                allow_single_file = True,
                cfg = "exec",
            ),
            "_stylish_formatter": attr.label(
                default = "@rules_lint//lint/js:eslint.stylish-formatter",
                allow_single_file = True,
                cfg = "exec",
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
        toolchains = COPY_FILE_TO_BIN_TOOLCHAINS + [OPTIONAL_SARIF_PARSER_TOOLCHAIN],
    )
