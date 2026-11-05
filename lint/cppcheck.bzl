"""API for calling declaring a cppcheck lint aspect.
"""

load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("@rules_cc//cc:defs.bzl", "CcInfo", "cc_common")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "noop_lint_action", "output_files", "parse_to_sarif_action", "should_visit")

_MNEMONIC = "AspectRulesLintCppCheck"

def _gather_inputs(compilation_context, srcs):
    inputs = srcs
    return depset(inputs, transitive = [compilation_context.headers])

# taken over from clang_tidy.bzl
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

# taken over from clang_tidy.bzl
# modification of filter_srcs in lint_aspect.bzl that filters out header files
def _filter_srcs(rule):
    # some rules can return a CcInfo without having a srcs attribute
    if not hasattr(rule.attr, "srcs"):
        return []
    if "lint-genfiles" in rule.attr.tags:
        return rule.files.srcs
    else:
        return [s for s in rule.files.srcs if _is_source(s)]

def _prefixed(list, prefix):
    array = []
    for arg in list:
        array.append("{}{}".format(prefix, arg))
    return array

def _get_compiler_args(compilation_context):
    # add includes
    args = []
    args.extend(_prefixed(compilation_context.framework_includes.to_list(), "-I"))
    args.extend(_prefixed(compilation_context.includes.to_list(), "-I"))
    args.extend(_prefixed(compilation_context.quote_includes.to_list(), "-I"))
    args.extend(_prefixed(compilation_context.system_includes.to_list(), "-I"))
    args.extend(_prefixed(compilation_context.external_includes.to_list(), "-I"))
    return args

def cppcheck_action(ctx, compilation_context, executable, srcs, stdout, exit_code, do_xml = False, args = []):
    """Create a Bazel Action that spawns a cppcheck process.

    Args:
        ctx: an action context OR aspect context
        compilation_context: from target
        executable: struct with a cppcheck field
        srcs: file objects to lint
        stdout: output file containing the stdout or --output-file of cppcheck
        exit_code: output file containing the exit code of cppcheck.
            If None, then fail the build when cppcheck exits non-zero.
        do_xml: If true, xml output is generated
        args: additional command-line arguments passed to cppcheck
    """

    outputs = [stdout]
    env = {}

    if not do_xml:
        env["CPPCHECK__STDOUT_STDERR_OUTPUT_FILE"] = stdout.path

    if exit_code:
        env["CPPCHECK__EXIT_CODE_OUTPUT_FILE"] = exit_code.path
        outputs.append(exit_code)

    env["CPPCHECK__VERBOSE"] = "1" if ctx.attr._verbose else ""

    cppcheck_args = list(args)

    # cppcheck shall fail with exit code != 0 if issues found
    cppcheck_args.append("--error-exitcode=31")

    # add include paths
    cppcheck_args.extend(_get_compiler_args(compilation_context))

    if do_xml:
        env["CPPCHECK__OUTPUT_FILE"] = stdout.path
        cppcheck_args.append("--xml-version=3")
    else:
        # The SARIF parser is keyed to this exact layout, so it is not user-overridable.
        # {severity} appears twice on purpose: errorformat consumes the leading copy to derive
        # the SARIF level, the copy in the tag survives into the message text. With
        # --report-type, cppcheck substitutes the coding-standard classification for {severity}
        # and the guideline for {id}.
        cppcheck_args.append("--template={file}:{line}:{column}: {severity}: {message} [{severity} {id}]")

    for f in srcs:
        cppcheck_args.append(f.short_path)

    ctx.actions.run_shell(
        inputs = _gather_inputs(compilation_context, srcs),
        outputs = outputs,
        tools = [executable._cppcheck_wrapper, executable._cppcheck, find_cpp_toolchain(ctx).all_files],
        command = executable._cppcheck_wrapper.path + ' "$@"',
        arguments = [executable._cppcheck.path] + cppcheck_args,
        env = env,
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with cppcheck",
    )

def _cppcheck_aspect_impl(target, ctx):
    if not CcInfo in target:
        return []

    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    files_to_lint = _filter_srcs(ctx.rule)
    compilation_context = target[CcInfo].compilation_context
    if hasattr(ctx.rule.attr, "implementation_deps"):
        compilation_context = cc_common.merge_compilation_contexts(
            compilation_contexts = [compilation_context] +
                                   [implementation_dep[CcInfo].compilation_context for implementation_dep in ctx.rule.attr.implementation_deps],
        )

    outputs, info = output_files(_MNEMONIC, target, ctx)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    cppcheck_action(ctx, compilation_context, ctx.executable, files_to_lint, outputs.human.out, outputs.human.exit_code, args = ctx.attr._args)

    parse_to_sarif_action(ctx, _MNEMONIC, outputs.human.out, outputs.machine.out)

    # The XML report is a deliverable of its own; unlike the text output it is lossless, keeping
    # the cppcheck id alongside the coding-standard guideline and classification.
    xml_output = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "xml"))
    cppcheck_action(ctx, compilation_context, ctx.executable, files_to_lint, xml_output, outputs.machine.exit_code, do_xml = True, args = ctx.attr._args)

    # Create new OutputGroupInfo with xml_output added to machine outputs
    info = OutputGroupInfo(
        rules_lint_human = info.rules_lint_human,
        rules_lint_machine = info.rules_lint_machine,
        rules_lint_xml = depset([xml_output]),
        _validation = info._validation,
    )
    return [info]

DEFAULT_RULE_KINDS = ["cc_binary", "cc_library"]

def lint_cppcheck_aspect(binary, verbose = False, rule_kinds = DEFAULT_RULE_KINDS, args = []):
    """A factory function to create a linter aspect.

    Args:
        binary: the cppcheck binary, typically a rule like

            ```starlark
            sh_binary(
                name = "cppcheck",
                srcs = [":cppcheck_wrapper.sh"],
            )
            ```
            As cppcheck does not support any configuration files so far, all arguments
            shall be directly implemented in the wrapper script. This file can also directly
            pass the license file to cppcheck, if needed.

            An example wrapper script could look like this:

            ```bash
            #!/bin/bash

            ~/.local/bin/cppcheck/cppcheck \
                --check-level=exhaustive \
                --enable=warning,style,performance,portability,information \
                "$@"
            ```

        verbose: print debug messages including cppcheck command lines being invoked.
        rule_kinds: which target kinds should be visited automatically
        args: additional options to pass to cppcheck.
    """

    return aspect(
        implementation = _cppcheck_aspect_impl,
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_verbose": attr.bool(
                default = verbose,
            ),
            "_args": attr.string_list(
                default = args,
            ),
            "_cppcheck": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_cppcheck_wrapper": attr.label(
                default = Label("@rules_lint//lint:cppcheck_wrapper"),
                executable = True,
                cfg = "exec",
            ),
            "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
        },
        toolchains = [
            OPTIONAL_SARIF_PARSER_TOOLCHAIN,
            "@bazel_tools//tools/cpp:toolchain_type",
        ],
        fragments = ["cpp"],
    )
