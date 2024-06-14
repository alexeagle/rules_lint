"""API for calling declaring a clang-tidy lint aspect.

Typical usage:

First, install clang-tidy with llvm_toolchain or as a native binary (llvm_toolchain
does not support Windows as of 06/2024, but providing a native clang-tidy.exe works)

Next, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

e.g. using llvm_toolchain:
```starlark
native_binary(
    name = "clang_tidy",
    src = "@llvm_toolchain_llvm//:bin/clang-tidy"
    out = "clang_tidy",
)
```

e.g as native binary:
```starlark
native_binary(
    name = "clang_tidy",
    src = "clang-tidy.exe"
    out = "clang_tidy",
)
```

Finally, create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@aspect_rules_lint//lint:clang_tidy.bzl", "clang_tidy_aspect")

clang_tidy = clang_tidy_aspect(
    binary = "@@//path/to:clang-tidy",
    configs = "@@//path/to:.clang-tidy",
)
```
"""

load("@aspect_bazel_lib//lib:copy_to_bin.bzl", "COPY_FILE_TO_BIN_TOOLCHAINS", "copy_files_to_bin_actions")
load("@aspect_rules_js//js:libs.bzl", "js_lib_helpers")
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "dummy_successful_lint_action", "filter_srcs", "report_files", "patch_and_report_files")

_MNEMONIC = "AspectRulesLintClangTidy"

###############################################
# START COPY CODE FROM private/lint_aspect.bzl
#
# this code needed to be changed to support generation of a report file
# per-source-file, rather than per-target.
###############################################
_OUTFILE_FORMAT = "{label}.{mnemonic}.{suffix}"

def _report_files_for_file(mnemonic, src, ctx):
    # TODO: not sure how to get the 'src/' prefix (the build file dir) programatically
    relative_file = src.path.removeprefix("src/")
    report = ctx.actions.declare_file(_OUTFILE_FORMAT.format(label = relative_file, mnemonic = mnemonic, suffix = "report"))
    outs = [report]
    if ctx.attr._options[LintOptionsInfo].fail_on_violation:
        # Fail on violation means the exit code is reported to Bazel as the action result
        exit_code = None
    else:
        # The exit code should instead be provided as an action output so the build succeeds.
        # Downstream tooling like `aspect lint` will be responsible for reading the exit codes
        # and interpreting them.
        exit_code = ctx.actions.declare_file(_OUTFILE_FORMAT.format(label = relative_file, mnemonic = mnemonic, suffix = "exit_code"))
        outs.append(exit_code)
    return report, exit_code, OutputGroupInfo(rules_lint_report = depset(outs))

def _patch_file_for_file(mnemonic, src, ctx):
    # TODO: not sure how to get the 'src/' prefix (the build file dir) programatically
    relative_file = src.path.removeprefix("src/")
    patch = ctx.actions.declare_file(_OUTFILE_FORMAT.format(label = relative_file, mnemonic = mnemonic, suffix = "patch"))
    return patch, OutputGroupInfo(rules_lint_patch = depset([patch]))
###############################################
# END COPY CODE FROM private/lint_aspect.bzl
###############################################

def _gather_inputs(ctx, compilation_context, src):
    # todo: handle header files in deps
    inputs = [src, ctx.file._config_file] + compilation_context.headers.to_list()
    return inputs

def _toolchain_flags(ctx, action_name = ACTION_NAMES.cpp_compile):
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = ctx.fragments.cpp.cxxopts + ctx.fragments.cpp.copts,
    )
    flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = compile_variables,
    )
    return flags

def _safe_flags(flags):
    # Some flags might be used by GCC, but not understood by Clang.
    # Remove them here, to allow users to run clang-tidy, without having
    # a clang toolchain configured (that would produce a good command line with --compiler clang)
    unsupported_flags = [
        "-fno-canonical-system-headers",
        "-fstack-usage",
        "/nologo",
        "/COMPILER_MSVC",
        "/showIncludes",
    ]

    return [flag for flag in flags if flag not in unsupported_flags and not flag.startswith("/wd")]

def add_all(array, list, **kwargs):
    if not "before_each" in kwargs:
        array = array + list
    else:
        for arg in list:
            array.append(kwargs["before_each"])
            array.append(arg)

def angle_includes_option(ctx):
    if (ctx.attr._angle_includes_are_system):
        return "-isystem"
    return "-I"
    
def _is_windows(ctx):
    # todo: how do I implement this?
    return False

# on linux, bazel will quote arguments that contain special characters, e.g. '-header-filter=.*/hello-world\.*'
# on windows, bazel does not do this. Workaround this for the regex option.
def _quote(ctx, string):
    if _is_windows(ctx):
        return "'"+string+"'"
    return string

def is_c(file):
    if file.extension == "c":
        return True
    return False

def get_args(ctx, compilation_context, src):
    args = []
    args.append(src.short_path)
    args.append("--config-file="+ctx.file._config_file.path)
    if (ctx.attr._lint_matching_header):
        base_filename = src.basename.removesuffix("."+src.extension)
        regex = _quote(ctx, ".*/"+base_filename+"\\.*")
        args.append("-header-filter="+regex)
    elif (ctx.attr._header_filter):
        regex = _quote(ctx, ctx.attr._header_filter)
        args.append("-header-filter="+regex)
    args.append("--")

    # add args specified by the toolchain, on the command line and rule copts
    rule_flags = ctx.rule.attr.copts if hasattr(ctx.rule.attr, "copts") else []
    if (is_c(src)):
        add_all(args, _safe_flags(_toolchain_flags(ctx, ACTION_NAMES.c_compile) + rule_flags) + ["-xc"])
    else:
        add_all(args, _safe_flags(_toolchain_flags(ctx, ACTION_NAMES.cpp_compile) + rule_flags) + ["-xc++"])

    # add defines
    for define in compilation_context.defines.to_list():
        args.append("-D" + define)
    for define in compilation_context.local_defines.to_list():
        args.append("-D" + define)

    # add includes
    add_all(args, compilation_context.framework_includes.to_list(), before_each = "-F")
    add_all(args, compilation_context.includes.to_list(), before_each = "-I")
    add_all(args, compilation_context.quote_includes.to_list(), before_each = "-iquote")
    add_all(args, compilation_context.system_includes.to_list(), before_each = angle_includes_option(ctx))
    add_all(args, compilation_context.external_includes.to_list(), before_each = "-isystem")

    args.append(src.short_path)
    return args

def clang_tidy_action(ctx, compilation_context, executable, src, stdout, exit_code):
    """Create a Bazel Action that spawns a clang-tidy process.

    Adapter for wrapping Bazel around
    https://clang.llvm.org/extra/clang-tidy/

    Args:
        ctx: an action context OR aspect context
        executable: struct with a clang-tidy field
        src: single file object to lint
        report: output file containing the stdout or --output-file of clang-tidy
        exit_code: output file containing the exit code of clang-tidy.
            If None, then fail the build when clang-tidy exits non-zero.
    """

    outputs = [stdout]
    if exit_code:
        command = "{clang_tidy} $@ >{stdout}; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        # Create empty stdout file on success, as Bazel expects one
        command = "{clang_tidy} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = _gather_inputs(ctx, compilation_context, src),
        outputs = outputs,
        tools = [executable._clang_tidy],
        command = command.format(clang_tidy = executable._clang_tidy.path, stdout = stdout.path),
        arguments = get_args(ctx, compilation_context, src),
        use_default_shell_env = True,
        #env = env,
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with clang-tidy",
    )

def clang_tidy_fix(ctx, compilation_context, executable, src, patch, stdout, exit_code):
    """Create a Bazel Action that spawns clang-tidy with --fix.

    Args:
        ctx: an action context OR aspect context
        executable: struct with a clang_tidy field
        srcs: list of file objects to lint
        patch: output file containing the applied fixes that can be applied with the patch(1) command.
        stdout: output file containing the stdout or --output-file of clang-tidy
        exit_code: output file containing the exit code of clang-tidy
    """
    patch_cfg = ctx.actions.declare_file("_{}.patch_cfg".format(ctx.label.name))

    args = get_args(ctx, compilation_context, src)
    ctx.actions.write(
        output = patch_cfg,
        content = json.encode({
            "linter": executable._clang_tidy.path,
            "args": ["--fix"] + get_args(ctx, compilation_context, src),
            "env": {"BAZEL_BINDIR": ctx.bin_dir.path},
            "files_to_diff": [src.path],
            "output": patch.path,
        }),
    )

    ctx.actions.run(
        inputs = _gather_inputs(ctx, compilation_context, src) + [patch_cfg],
        outputs = [patch, stdout, exit_code],
        executable = executable._patcher,
        arguments = [patch_cfg.path],
        env = {"BAZEL_BINDIR": "."},
        tools = [executable._clang_tidy],
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with clang-tidy",
    )

# buildifier: disable=function-docstring
def _clang_tidy_aspect_impl(target, ctx):
    if not CcInfo in target:
        return []

    # todo: keep this? #Ignore external targets
    #if target.label.workspace_root.startswith("external"):
    #    return []

    # Targets with specific tags will not be formatted
    ignore_tags = [
        "noclangtidy",
        "no-clang-tidy",
    ]

    for tag in ignore_tags:
        if tag in ctx.rule.attr.tags:
            return []

    files_to_lint = filter_srcs(ctx.rule)
    #files_to_lint = _rule_sources(ctx)

    # handle zero-files case and keep bazel happy by returning something
    if not any(files_to_lint):
        if ctx.attr._options[LintOptionsInfo].fix:
            patch, report, exit_code, info = patch_and_report_files(_MNEMONIC, target, ctx)
            dummy_successful_lint_action(ctx, report, exit_code, patch)
        else:
            report, exit_code, info = report_files(_MNEMONIC, target, ctx)
            dummy_successful_lint_action(ctx, report, exit_code)
    else:
        compilation_context = target[CcInfo].compilation_context
        reports = []
        patches = []
        # todo: I really don't know the best way to handle multiple inputs, and that clang-tidy
        # supports only one at a time. I'm not sure where the loop should go, and how to integrate
        # with the various report helpers from aspect.
        for file_to_lint in files_to_lint:
            report, exit_code, _ = _report_files_for_file(_MNEMONIC, file_to_lint, ctx)
            reports.append(report)
            if (exit_code):
                reports.append(exit_code)
            if ctx.attr._options[LintOptionsInfo].fix:
                patch, _ = _patch_file_for_file(_MNEMONIC, file_to_lint, ctx)
                patches.append(patch)
                clang_tidy_fix(ctx, compilation_context, ctx.executable, file_to_lint, patch, report, exit_code)
            else:
                clang_tidy_action(ctx, compilation_context, ctx.executable, file_to_lint, report, exit_code)
        info = [OutputGroupInfo(
            rules_lint_report = depset(reports),
            rules_lint_patch = depset(patches),
        )]
    return info

def lint_clang_tidy_aspect(binary, config, **kwargs):
    """A factory function to create a linter aspect.

    Args:
        binary: the clang-tidy binary, typically a rule like

        ```starlark
        native_binary(
            name = "clang_tidy",
            src = "clang-tidy.exe"
            out = "clang_tidy",
        )
        ```
        config: label of the .clang-tidy file
        header_filter: optional, set to a posix regex to supply to clang-tidy with the -header-filter option
        lint_matching_header: optional, set to True to include the matching header file
        in the lint output results for each source. If supplied, overrides the header_filter option.
        angle_includes_are_system: controls how angle includes are passed to clang-tidy. By default, Bazel
        passes these as -isystem. Change this to False to pass these as -I, which allows clang-tidy to regard
        them as regular header files.
    """

    return aspect(
        implementation = _clang_tidy_aspect_impl,
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_lint_matching_header": attr.bool(
                default = kwargs.get("lint_matching_header", False),
            ),
            "_header_filter": attr.string(
            ),
            "_angle_includes_are_system": attr.bool(
                default = kwargs.get("angle_includes_are_system", True)
            ),
            "_clang_tidy": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_config_file": attr.label(
                default = config,
                allow_single_file = True,
            ),
            "_patcher": attr.label(
                default = "@aspect_rules_lint//lint/private:patcher",
                executable = True,
                cfg = "exec",
            ),
            "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
        },
        toolchains = COPY_FILE_TO_BIN_TOOLCHAINS + ["@bazel_tools//tools/cpp:toolchain_type"],
        fragments = ["cpp"],
    )
