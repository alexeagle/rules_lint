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
load("@aspect_rules_lint//lint:clang_tidy.bzl", "lint_clang_tidy_aspect")

clang_tidy = lint_clang_tidy_aspect(
    binary = "@@//path/to:clang-tidy",
    configs = "@@//path/to:.clang-tidy",
)
```
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "noop_lint_action", "output_files", "patch_and_output_files")

_MNEMONIC = "AspectRulesLintClangTidy"
_DISABLED_FEATURES = [
    "layering_check",
]

def _gather_inputs(ctx, compilation_context, srcs):
    inputs = srcs + ctx.files._configs
    if (any(ctx.files._global_config)):
        inputs.append(ctx.files._global_config[0])
    return depset(inputs, transitive = [compilation_context.headers])

def _toolchain_env(ctx, user_flags, action_name = ACTION_NAMES.cpp_compile):
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features + _DISABLED_FEATURES,
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = user_flags,
    )
    env = {}
    env.update(cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = compile_variables,
    ))
    return env

def _toolchain_flags(ctx, user_flags, action_name = ACTION_NAMES.cpp_compile):
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features + _DISABLED_FEATURES,
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = user_flags,
    )
    flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = compile_variables,
    )
    return flags

def _update_flag(flag):
    # update from MSVC C++ standard to clang C++ standard
    unsupported_flags = [
        "-fno-canonical-system-headers",
        "-fstack-usage",
        "/nologo",
        "/COMPILER_MSVC",
        "/showIncludes",
        "/experimental:external",
    ]
    unsupported_prefixes = [
        "/wd",
        "-W",
        "/W",
        "/external",
    ]
    if (flag in unsupported_flags):
        return []
    for prefix in unsupported_prefixes:
        if flag.startswith(prefix):
            return []

    flags = [flag]

    # remap MSVC flags to clang-style
    if (flag.startswith("/std:")):
        # remap c++ standard to clang
        flags = ["-std=" + flag.removeprefix("/std:")]
    elif (flag.startswith("/D")):
        # remap defines
        flags = ["-" + flag[1:]]
    elif (flag.startswith("/FI")):
        flags = ["-include", flag.removeprefix("/FI")]
    elif (flag.startswith("/I")):
        flags = ["-iquote", flag.removeprefix("/I")]
    elif (flag in ["/MD", "/MDd", "/MT", "/MTd"]):
        # mimic microsoft's behaviour and add a define
        flags = ["-D_MT"]
    elif (flag.startswith("/")):
        # strip all other microsoft params
        return []
    return flags

def _safe_flags(ctx, flags):
    # Some flags might be used by GCC/MSVC, but not understood by Clang.
    # Remap or remove them here, to allow users to run clang-tidy, without having
    # a clang toolchain configured (that would produce a good command line with --compiler clang)
    safe_flags = []
    skipped_flags = []
    for flag in flags:
        updated = _update_flag(flag)
        if (any(updated)):
            safe_flags.extend(updated)
        elif (ctx.attr._verbose):
            skipped_flags.append(flag)
    if (ctx.attr._verbose and any(skipped_flags)):
        # buildifier: disable=print
        print("skipped flags: " + " ".join(skipped_flags))
    return safe_flags

def _prefixed(list, prefix):
    array = []
    for arg in list:
        array.append(prefix)
        array.append(arg)
    return array

def _angle_includes_option(ctx):
    if (ctx.attr._angle_includes_are_system):
        return "-isystem"
    return "-I"

def _is_cxx(file):
    return not file.extension == "c"

def _is_source(file):
    permitted_source_types = [
        "c",
        "cc",
        "cpp",
        "cxx",
        "c++",
        "C",
    ]
    return (file.is_source and file.extension in permitted_source_types)

# modification of filter_srcs in lint_aspect.bzl that filters out header files
def _filter_srcs(rule):
    if "lint-genfiles" in rule.attr.tags:
        return rule.files.srcs
    else:
        return [s for s in rule.files.srcs if _is_source(s)]

def is_parent_in_list(dir, list):
    for item in list:
        if (dir != item and dir.startswith(item)):
            return True
    return False

def _common_prefixes(headers):
    # crude code to work out a common directory prefix for all headers
    # is there a canonical way to do this in starlark?
    dirs = []
    for h in headers:
        dir = h.dirname
        if dir not in dirs:
            dirs.append(dir)
    dirs2 = []
    for dir in dirs:
        if (not is_parent_in_list(dir, dirs)):
            dirs2.append(dir)
    return dirs2

def _aggregate_regex(ctx, compilation_context):
    if not any(compilation_context.direct_headers):
        return None
    dirs = _common_prefixes(compilation_context.direct_headers)
    if not any(dirs):
        regex = None
    elif len(dirs) == 1:
        # clang-tidy reports headers with mixed '\\' and '/' separators on windows. Match either.
        regex_dir = dirs[0].replace("\\", "[\\/]").replace("/", "[\\/]")
        regex = ".*" + regex_dir + "/.*"
    else:
        regex = ".*"
    if (ctx.attr._verbose):
        # buildifier: disable=print
        print("target header dirs: " + ",".join(dirs))
    return regex

def _quoted_arg(arg):
    return "\"" + arg + "\""

def _get_env(ctx, srcs):
    sources_are_cxx = _is_cxx(srcs[0])
    if (sources_are_cxx):
        user_flags = ctx.fragments.cpp.cxxopts + ctx.fragments.cpp.copts
        env = _toolchain_env(ctx, user_flags, ACTION_NAMES.cpp_compile)
    else:
        user_flags = ctx.fragments.cpp.copts
        env = _toolchain_env(ctx, user_flags, ACTION_NAMES.c_compile)
    if (ctx.attr._verbose):
        env["CLANG_TIDY__VERBOSE"] = "1"

    # in case we are running in msys bash, stop it from mangling pathnames
    env["MSYS_NO_PATHCONV"] = "1"
    env["MSYS_ARG_CONV_EXCL"] = "*"
    return env

def _get_args(ctx, compilation_context, srcs):
    args = []
    if (any(ctx.files._global_config)):
        args.append("--config-file=" + ctx.files._global_config[0].short_path)
    if (ctx.attr._lint_target_headers):
        regex = _aggregate_regex(ctx, compilation_context)
        if (regex):
            args.append(_quoted_arg("-header-filter=" + regex))
    elif (ctx.attr._header_filter):
        regex = ctx.attr._header_filter
        args.append(_quoted_arg("-header-filter=" + regex))
    args.extend([src.short_path for src in srcs])
    return args

def _get_compiler_args(ctx, compilation_context, srcs):
    # add args specified by the toolchain, on the command line and rule copts
    args = []
    rule_flags = ctx.rule.attr.copts if hasattr(ctx.rule.attr, "copts") else []
    sources_are_cxx = _is_cxx(srcs[0])
    if (sources_are_cxx):
        user_flags = ctx.fragments.cpp.cxxopts + ctx.fragments.cpp.copts
        args.extend(_safe_flags(ctx, _toolchain_flags(ctx, user_flags, ACTION_NAMES.cpp_compile) + rule_flags) + ["-xc++"])
    else:
        user_flags = ctx.fragments.cpp.copts
        args.extend(_safe_flags(ctx, _toolchain_flags(ctx, user_flags, ACTION_NAMES.c_compile) + rule_flags) + ["-xc"])

    # add defines
    for define in compilation_context.defines.to_list():
        args.append("-D" + define)
    for define in compilation_context.local_defines.to_list():
        args.append("-D" + define)

    # add includes
    args.extend(_prefixed(compilation_context.framework_includes.to_list(), "-F"))
    args.extend(_prefixed(compilation_context.includes.to_list(), "-I"))
    args.extend(_prefixed(compilation_context.quote_includes.to_list(), "-iquote"))
    args.extend(_prefixed(compilation_context.system_includes.to_list(), _angle_includes_option(ctx)))
    args.extend(_prefixed(compilation_context.external_includes.to_list(), "-isystem"))
    return args

def clang_tidy_action(ctx, compilation_context, executable, srcs, stdout, exit_code):
    """Create a Bazel Action that spawns a clang-tidy process.

    Adapter for wrapping Bazel around
    https://clang.llvm.org/extra/clang-tidy/

    Args:
        ctx: an action context OR aspect context
        compilation_context: from target
        executable: struct with a clang-tidy field
        srcs: file objects to lint
        stdout: output file containing the stdout or --output-file of clang-tidy
        exit_code: output file containing the exit code of clang-tidy.
            If None, then fail the build when clang-tidy exits non-zero.
    """

    outputs = [stdout]
    env = _get_env(ctx, srcs)
    env["CLANG_TIDY__STDOUT_STDERR_OUTPUT_FILE"] = stdout.path

    if exit_code:
        env["CLANG_TIDY__EXIT_CODE_OUTPUT_FILE"] = exit_code.path
        outputs.append(exit_code)

    # pass compiler args via a params file. The command line may already be long due to
    # sources, which can't go the params file, so materialize it always.
    clang_tidy_args = _get_args(ctx, compilation_context, srcs)
    compiler_args = ctx.actions.args()
    compiler_args.add_all(_get_compiler_args(ctx, compilation_context, srcs))
    compiler_args.use_param_file("--config %s", use_always = True)

    ctx.actions.run_shell(
        inputs = _gather_inputs(ctx, compilation_context, srcs),
        outputs = outputs,
        tools = [executable._clang_tidy_wrapper, executable._clang_tidy, find_cpp_toolchain(ctx).all_files],
        command = executable._clang_tidy_wrapper.path + " $@",
        arguments = [executable._clang_tidy.path] + clang_tidy_args + ["--", compiler_args],
        env = env,
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with clang-tidy",
    )

def clang_tidy_fix(ctx, compilation_context, executable, srcs, patch, stdout, exit_code):
    """Create a Bazel Action that spawns clang-tidy with --fix.

    Args:
        ctx: an action context OR aspect context
        compilation_context: from target
        executable: struct with a clang_tidy field
        srcs: list of file objects to lint
        patch: output file containing the applied fixes that can be applied with the patch(1) command.
        stdout: output file containing the stdout or --output-file of clang-tidy
        exit_code: output file containing the exit code of clang-tidy
    """
    patch_cfg = ctx.actions.declare_file("_{}.patch_cfg".format(ctx.label.name))
    clang_tidy_args = _get_args(ctx, compilation_context, srcs)
    compiler_args = _get_compiler_args(ctx, compilation_context, srcs)

    ctx.actions.write(
        output = patch_cfg,
        content = json.encode({
            "linter": executable._clang_tidy_wrapper.path,
            "args": [executable._clang_tidy.path, "--fix"] + clang_tidy_args + ["--"] + compiler_args,
            "env": _get_env(ctx, srcs),
            "files_to_diff": [src.path for src in srcs],
            "output": patch.path,
        }),
    )

    ctx.actions.run(
        inputs = depset([patch_cfg], transitive = [_gather_inputs(ctx, compilation_context, srcs)]),
        outputs = [patch, stdout, exit_code],
        executable = executable._patcher,
        arguments = [patch_cfg.path],
        env = {
            "BAZEL_BINDIR": ".",
            "JS_BINARY__EXIT_CODE_OUTPUT_FILE": exit_code.path,
            "JS_BINARY__STDOUT_OUTPUT_FILE": stdout.path,
            "JS_BINARY__SILENT_ON_SUCCESS": "1",
        },
        tools = [executable._clang_tidy_wrapper, executable._clang_tidy, find_cpp_toolchain(ctx).all_files],
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with clang-tidy",
    )

# buildifier: disable=function-docstring
def _clang_tidy_aspect_impl(target, ctx):
    if not CcInfo in target:
        return []

    files_to_lint = _filter_srcs(ctx.rule)
    compilation_context = target[CcInfo].compilation_context
    if hasattr(ctx.rule.attr, "implementation_deps"):
        compilation_context = cc_common.merge_compilation_contexts(
            compilation_contexts = [compilation_context] +
                [implementation_dep[CcInfo].compilation_context for implementation_dep in ctx.rule.attr.implementation_deps])

    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(_MNEMONIC, target, ctx)
    else:
        outputs, info = output_files(_MNEMONIC, target, ctx)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    if hasattr(outputs, "patch"):
        clang_tidy_fix(ctx, compilation_context, ctx.executable, files_to_lint, outputs.patch, outputs.human.out, outputs.human.exit_code)
    else:
        clang_tidy_action(ctx, compilation_context, ctx.executable, files_to_lint, outputs.human.out, outputs.human.exit_code)

    # TODO(alex): if we run with --fix, this will report the issues that were fixed. Does a machine reader want to know about them?
    clang_tidy_action(ctx, compilation_context, ctx.executable, files_to_lint, outputs.machine.out, outputs.machine.exit_code)
    return [info]

def lint_clang_tidy_aspect(binary, configs = [], global_config = [], header_filter = "", lint_target_headers = False, angle_includes_are_system = True, verbose = False):
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
        configs: labels of the .clang-tidy files to make available to clang-tidy's config search. These may be
            in subdirectories and clang-tidy will apply them if appropriate. This may also include .clang-format
            files which may be used for formatting fixes.
        global_config: label of a single global .clang-tidy file to pass to clang-tidy on the command line. This
            will cause clang-tidy to ignore any other config files in the source directories.
        header_filter: optional, set to a posix regex to supply to clang-tidy with the -header-filter option
        lint_target_headers: optional, set to True to pass a pattern that includes all headers with the target's
            directory prefix. This crude control may include headers from the linted target in the results. If
            supplied, overrides the header_filter option.
        angle_includes_are_system: controls how angle includes are passed to clang-tidy. By default, Bazel
            passes these as -isystem. Change this to False to pass these as -I, which allows clang-tidy to regard
            them as regular header files.
        verbose: print debug messages including clang-tidy command lines being invoked.
    """

    if type(global_config) == "string":
        global_config = [global_config]

    return aspect(
        implementation = _clang_tidy_aspect_impl,
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_configs": attr.label_list(
                default = configs,
                allow_files = True,
            ),
            "_global_config": attr.label_list(
                default = global_config,
                allow_files = True,
            ),
            "_lint_target_headers": attr.bool(
                default = lint_target_headers,
            ),
            "_header_filter": attr.string(
                default = header_filter,
            ),
            "_angle_includes_are_system": attr.bool(
                default = angle_includes_are_system,
            ),
            "_verbose": attr.bool(
                default = verbose,
            ),
            "_clang_tidy": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_clang_tidy_wrapper": attr.label(
                default = Label("@aspect_rules_lint//lint:clang_tidy_wrapper"),
                executable = True,
                cfg = "exec",
            ),
            "_patcher": attr.label(
                default = "@aspect_rules_lint//lint/private:patcher",
                executable = True,
                cfg = "exec",
            ),
            "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
        },
        toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
        fragments = ["cpp"],
    )
