"""API for declaring a Buildifier lint aspect for Starlark sources.

Typical usage:

First, add `buildifier_prebuilt` in `MODULE.bazel`:

```starlark
bazel_dep(name = "buildifier_prebuilt", version = "8.5.1")
```

Then create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:buildifier.bzl", "lint_buildifier_aspect")

buildifier = lint_buildifier_aspect(
    binary = Label("@buildifier_prebuilt//:buildifier"),
)
```

The aspect visits `bzl_library` targets by default. To lint files such as
`BUILD.bazel`, `MODULE.bazel`, or custom Starlark files, add `tags = ["starlark"]`
or `tags = ["lint-with-buildifier"]` to a target that lists those files in `srcs`.

```starlark
filegroup(
    name = "starlark_files",
    srcs = ["BUILD.bazel", "MODULE.bazel", "defs.star"],
    tags = ["starlark"],
)
```
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "patch_and_output_files", "should_visit")
load("//lint/private:patcher_action.bzl", "patcher_attrs", "run_patcher")

_MNEMONIC = "AspectRulesLintBuildifier"

def buildifier_action(ctx, tool, srcs, stdout = None, exit_code = None, patch = None, args = []):
    """Run Buildifier as an action under Bazel.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        tool: FilesToRunProvider for the Buildifier program
        srcs: Starlark files to lint
        stdout: output file containing stdout/stderr from Buildifier
        exit_code: optional output file containing the exit code
        patch: optional output file for a generated patch
        args: additional command-line options
    """
    executable = tool.executable

    if patch != None:
        wrapper = ctx.actions.declare_file(ctx.label.name + ".buildifier_wrapper.sh")
        action_args = ctx.actions.args()
        action_args.add("--warnings={}".format(ctx.attr._warnings))
        action_args.add_all(args)
        action_args.add_all(srcs)

        ctx.actions.write(
            output = wrapper,
            content = """#!/bin/bash
"{buildifier}" --lint=fix "$@"
"{buildifier}" --lint=warn "$@" 2>&1
""".format(buildifier = executable.path),
            is_executable = True,
        )

        run_patcher(
            ctx,
            ctx.executable,
            inputs = srcs,
            args = action_args,
            files_to_diff = [src.path for src in srcs],
            patch_out = patch,
            tools = [wrapper, tool],
            stdout = stdout,
            exit_code = exit_code,
            mnemonic = _MNEMONIC,
            progress_message = "Fixing %{label} with Buildifier",
        )
    else:
        action_args = ctx.actions.args()
        action_args.add("--lint=warn")
        action_args.add("--warnings={}".format(ctx.attr._warnings))
        action_args.add_all(args)
        action_args.add_all(srcs)
        outputs = [stdout]

        if exit_code:
            command = "{buildifier} $@ >{stdout} 2>&1; echo $? > " + exit_code.path
            outputs.append(exit_code)
        else:
            command = "{buildifier} $@ && touch {stdout}"

        ctx.actions.run_shell(
            inputs = srcs,
            outputs = outputs,
            tools = [tool],
            arguments = [action_args],
            command = command.format(buildifier = executable.path, stdout = stdout.path),
            mnemonic = _MNEMONIC,
            progress_message = "Linting %{label} with Buildifier",
        )

def _buildifier_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds, ctx.attr._filegroup_tags):
        return []

    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(_MNEMONIC, target, ctx)
    else:
        outputs, info = output_files(_MNEMONIC, target, ctx)

    files_to_lint = filter_srcs(ctx.rule)
    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    buildifier_action(
        ctx,
        ctx.attr._buildifier[DefaultInfo].files_to_run,
        files_to_lint,
        outputs.human.out,
        outputs.human.exit_code,
        patch = getattr(outputs, "patch", None),
        args = ctx.attr._args,
    )

    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    buildifier_action(
        ctx,
        ctx.attr._buildifier[DefaultInfo].files_to_run,
        files_to_lint,
        raw_machine_report,
        outputs.machine.exit_code,
        args = ctx.attr._args,
    )

    # Buildifier does not have a SARIF output mode, so we need to parse the raw machine report into SARIF format in a separate action.
    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)

    return [info]

def lint_buildifier_aspect(binary, warnings = "all", rule_kinds = ["bzl_library", "bzl_library_rule"], filegroup_tags = ["starlark", "lint-with-buildifier"], args = []):
    """A factory function to create a Buildifier linter aspect.

    Args:
        binary: a Buildifier executable, for example `@buildifier_prebuilt//:buildifier`
        warnings: value for Buildifier's `--warnings` flag
        rule_kinds: which target kinds should be visited automatically
        filegroup_tags: which target tags opt a target into Buildifier linting
        args: Additional options to pass to Buildifier
    """
    return aspect(
        implementation = _buildifier_aspect_impl,
        attrs = patcher_attrs | {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_buildifier": attr.label(
                default = binary,
                allow_files = True,
                executable = True,
                cfg = "exec",
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
            "_filegroup_tags": attr.string_list(
                default = filegroup_tags,
            ),
            "_warnings": attr.string(
                default = warnings,
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
        toolchains = [OPTIONAL_SARIF_PARSER_TOOLCHAIN],
    )
