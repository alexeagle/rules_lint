"""API for declaring a keep-sorted lint aspect that visits all source files.

Typical usage:

First, fetch the keep-sorted dependency via gazelle. We provide a convenient go.mod file.
To keep it isolated from your other go dependencies, we recommend adding to .bazelrc:

    common --experimental_isolated_extension_usages

Next add to MODULE.bazel:

    keep_sorted_deps = use_extension("@gazelle//:extensions.bzl", "go_deps", isolate = True)
    keep_sorted_deps.from_file(go_mod = "@rules_lint//lint/keep-sorted:go.mod")
    use_repo(keep_sorted_deps, "com_github_google_keep_sorted")

Finally, create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:keep_sorted.bzl", "lint_keep_sorted_aspect")

keep_sorted = lint_keep_sorted_aspect(
    binary = Label("@com_github_google_keep_sorted//:keep-sorted"),
)
```

Now you can add `// keep-sorted start` / `// keep-sorted end` lines to your library sources,
following the documentation at https://github.com/google/keep-sorted#usage.
"""

load("@jq.bzl//jq:jq.bzl", "jq_lib")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "patch_and_output_files", "should_visit")
load("//lint/private:patcher_action.bzl", "patcher_attrs", "run_patcher")

_MNEMONIC = "AspectRulesLintKeepSorted"

def keep_sorted_action(ctx, executable, srcs, stdout, exit_code = None, args = [], patch = None):
    """Run keep-sorted as an action under Bazel.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the keep-sorted program
        srcs: files to be linted
        stdout: output file containing stdout
        exit_code: output file containing exit code
            If None, then fail the build when program exits non-zero.
        args: additional command-line options
        patch: output file for patch (optional). If provided, uses run_patcher instead of run_shell.
    """
    inputs = srcs

    action_args = ctx.actions.args()
    action_args.add_all(args)
    action_args.add("--mode", "fix" if patch != None else "lint")
    action_args.add_all(srcs)

    if patch != None:
        # Use run_patcher for fix mode
        run_patcher(
            ctx,
            ctx.executable,
            inputs = inputs,
            args = action_args,
            files_to_diff = [s.path for s in srcs],
            patch_out = patch,
            tools = [executable],
            stdout = stdout,
            exit_code = exit_code,
            mnemonic = _MNEMONIC,
            progress_message = "Fixing %{label} with KeepSorted",
            patch_cfg_suffix = "keep-sorted.patch_cfg",
        )
    else:
        # Use run_shell for lint mode
        outputs = [stdout]

        if exit_code:
            command = "{keep_sorted} $@ >{stdout}; echo $? > " + exit_code.path
            outputs.append(exit_code)
        else:
            # Create empty stdout file on success, as Bazel expects one
            command = "{keep_sorted} $@ && touch {stdout}"

        ctx.actions.run_shell(
            inputs = inputs,
            outputs = outputs,
            tools = [executable],
            command = command.format(keep_sorted = executable.path, stdout = stdout.path),
            arguments = [action_args],
            mnemonic = _MNEMONIC,
            progress_message = "Linting %{label} with KeepSorted",
        )

def _keep_sorted_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ["*"]):
        return []

    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(_MNEMONIC, target, ctx)
    else:
        outputs, info = output_files(_MNEMONIC, target, ctx)

    if not hasattr(ctx.rule.attr, "srcs"):
        noop_lint_action(ctx, outputs)
        return [info]

    files_to_lint = filter_srcs(ctx.rule)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    color_options = ["--color=always"] if ctx.attr._options[LintOptionsInfo].color else []
    keep_sorted_action(
        ctx,
        ctx.executable._keep_sorted,
        files_to_lint,
        outputs.human.out,
        outputs.human.exit_code,
        args = color_options + ctx.attr._args,
        patch = getattr(outputs, "patch", None),
    )
    raw_json_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_json_report"))
    keep_sorted_action(ctx, ctx.executable._keep_sorted, files_to_lint, raw_json_report, outputs.machine.exit_code, args = ctx.attr._args)
    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    jq_lib.jq_action(ctx, [raw_json_report], ".[] | [.path, .lines.start, .lines.end, .message] | join(\":\")", raw_machine_report, ["--raw-output"])
    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)
    return [info]

def lint_keep_sorted_aspect(binary, args = []):
    """A factory function to create a linter aspect.

    Args:
        binary: a keep-sorted executable
        args: additional command-line arguments to pass to keep-sorted

    Returns:
        An aspect definition for keep-sorted
    """
    return aspect(
        implementation = _keep_sorted_aspect_impl,
        attrs = patcher_attrs | {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_keep_sorted": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
        toolchains = [
            "@jq.bzl//jq/toolchain:type",
            OPTIONAL_SARIF_PARSER_TOOLCHAIN,
        ],
    )
