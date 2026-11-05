"""API for declaring a Standard Ruby lint aspect.

Visits rb_{binary|library|test} rules.

Typical usage:

## Installing Standard Ruby

The recommended approach is to use Bundler with rules_ruby to manage
Standard Ruby as a gem dependency:

1. Add Standard Ruby to your `Gemfile`:
```ruby
gem "standard", "~> 1.0"
```

2. Run `bundle lock` to generate `Gemfile.lock`

3. Configure the bundle in your `MODULE.bazel`:
```starlark
ruby = use_extension("@rules_ruby//ruby:extensions.bzl", "ruby")
ruby.toolchain(
    name = "ruby",
    version = "3.3.0",
)
ruby.bundle_fetch(
    name = "bundle",
    gemfile = "//:Gemfile",
    gemfile_lock = "//:Gemfile.lock",
)
use_repo(ruby, "bundle", "ruby", "ruby_toolchains")
```

4. Create an alias to the gem-provided binary in
   `tools/lint/BUILD.bazel`:
```starlark
alias(
    name = "standardrb",
    actual = "@bundle//bin:standardrb",
)
```

5. Create the linter aspect, typically in `tools/lint/linters.bzl`:
```starlark
load("@rules_lint//lint:standardrb.bzl", "lint_standardrb_aspect")

standardrb = lint_standardrb_aspect(
    binary = "//tools/lint:standardrb",
    configs = ["//:standard.yml"],
)
```

This approach ensures:
- Hermetic builds with pinned gem versions
- Consistent Standard Ruby versions across all developers
- Integration with Bazel's dependency management

## Configuration

Standard Ruby will automatically discover `.standard.yml` files according to its
standard configuration hierarchy.
See https://github.com/standardrb/standard for details.

Note: all config files are passed to the action as inputs.
This means that a change to any config file invalidates the action cache
entries for ALL Standard Ruby actions.
"""

load(
    "//lint/private:lint_aspect.bzl",
    "LintOptionsInfo",
    "OPTIONAL_SARIF_PARSER_TOOLCHAIN",
    "OUTFILE_FORMAT",
    "filter_srcs",
    "noop_lint_action",
    "output_files",
    "parse_to_sarif_action",
    "patch_and_output_files",
    "should_visit",
)
load("//lint/private:patcher_action.bzl", "patcher_attrs", "run_patcher")

_MNEMONIC = "AspectRulesLintStandardRB"

def _build_standardrb_command(
        standardrb_path,
        stdout_path,
        exit_code_path = None):
    """Build shell command for running Standard Ruby.

    Args:
        standardrb_path: path to the Standard Ruby executable
        stdout_path: path where stdout/stderr should be written
        exit_code_path: path where exit code should be written. If None,
            the command will fail on non-zero exit.

    Returns:
        Fully formatted shell command string
    """
    cmd_parts = [
        "{standardrb} $@ >{stdout} 2>&1".format(
            standardrb = standardrb_path,
            stdout = stdout_path,
        ),
    ]
    if exit_code_path:
        cmd_parts.append(
            "; echo $? >{exit_code}".format(exit_code = exit_code_path),
        )
    return "".join(cmd_parts)

def standardrb_action(
        ctx,
        executable,
        srcs,
        config,
        stdout,
        exit_code = None,
        color = False,
        patch = None,
        args = []):
    """Run Standard Ruby as an action under Bazel.

    Standard Ruby will select the configuration file to use for each
    source file, as documented here:
    https://github.com/standardrb/standard

    Note: all config files are passed to the action.
    This means that a change to any config file invalidates the action cache
    entries for ALL Standard Ruby actions.

    However, this is important because Standard Ruby's logic for selecting the
    appropriate config needs to traverse the directory hierarchy.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: File object for the Standard Ruby executable
        srcs: list of File objects for Ruby source files to be linted
        config: list of File objects for Standard Ruby config files
            (.standard.yml)
        stdout: File object where linter output will be written
        exit_code: File object where exit code will be written, or None.
            If None, the build will fail when Standard Ruby exits non-zero.
            See https://github.com/standardrb/standard
        color: boolean, whether to enable color output
        patch: output file for patch (optional). If provided, uses run_patcher instead of run_shell.
        args: additional command-line arguments to pass to Standard Ruby
    """
    inputs = srcs + config
    if patch != None:
        # Use run_patcher for fix mode
        standardrb_args = (
            args +
            ["--fix", "--cache", "false"] +
            (["--color"] if color else []) +
            [s.path for s in srcs]
        )
        run_patcher(
            ctx,
            ctx.executable,
            inputs = inputs,
            args = standardrb_args,
            files_to_diff = [s.path for s in srcs],
            patch_out = patch,
            tools = [executable],
            stdout = stdout,
            exit_code = exit_code,
            mnemonic = _MNEMONIC,
            progress_message = "Fixing %{label} with Standard Ruby",
            patch_cfg_suffix = "standardrb.patch_cfg",
        )
    else:
        # Use run_shell for lint mode
        outputs = [stdout]
        action_args = ctx.actions.args()
        action_args.add_all(args)
        action_args.add("--format", "simple")
        action_args.add("--force-exclusion")
        action_args.add("--cache-root", "/tmp")
        action_args.add("--no-fix")
        if color:
            action_args.add("--color")
        action_args.add_all(srcs)

        command = _build_standardrb_command(
            executable.path,
            stdout.path,
            exit_code.path if exit_code else None,
        )
        if exit_code:
            outputs.append(exit_code)

        ctx.actions.run_shell(
            inputs = inputs,
            outputs = outputs,
            command = command,
            arguments = [action_args],
            mnemonic = _MNEMONIC,
            progress_message = "Linting %{label} with Standard Ruby",
            tools = [executable],
        )

# buildifier: disable=function-docstring
def _standardrb_aspect_impl(target, ctx):
    if not should_visit(
        ctx.rule,
        ctx.attr._rule_kinds,
        ctx.attr._filegroup_tags,
    ):
        return []

    files_to_lint = filter_srcs(ctx.rule)
    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(_MNEMONIC, target, ctx)
    else:
        outputs, info = output_files(_MNEMONIC, target, ctx)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    standardrb_action(
        ctx,
        ctx.executable._standardrb,
        files_to_lint,
        ctx.files._config_files,
        outputs.human.out,
        outputs.human.exit_code,
        color = ctx.attr._options[LintOptionsInfo].color,
        patch = getattr(outputs, "patch", None),
        args = ctx.attr._args,
    )

    # Generate machine-readable report in JSON format for SARIF conversion
    raw_machine_report = ctx.actions.declare_file(
        OUTFILE_FORMAT.format(
            label = target.label.name,
            mnemonic = _MNEMONIC,
            suffix = "raw_machine_report",
        ),
    )

    # Create separate action for JSON output
    json_args = ctx.actions.args()
    json_args.add_all(ctx.attr._args)

    # Use JSON format for machine-readable output (converted to SARIF)
    json_args.add("--format", "json")

    # Honor exclusions in .standard.yml even though we pass explicit list of
    # files
    json_args.add("--force-exclusion")

    # Disable caching as Bazel handles caching at the action level
    json_args.add("--cache", "false")
    json_args.add_all(files_to_lint)

    outputs_list = [raw_machine_report]
    command = _build_standardrb_command(
        ctx.executable._standardrb.path,
        raw_machine_report.path,
        outputs.machine.exit_code.path if outputs.machine.exit_code else None,
    )
    if outputs.machine.exit_code:
        outputs_list.append(outputs.machine.exit_code)

    ctx.actions.run_shell(
        inputs = files_to_lint + ctx.files._config_files,
        outputs = outputs_list,
        command = command,
        arguments = [json_args],
        mnemonic = _MNEMONIC,
        progress_message = """\
Generating machine-readable report for %{label} with Standard Ruby\
""",
        tools = [ctx.executable._standardrb],
    )

    parse_to_sarif_action(
        ctx,
        _MNEMONIC,
        raw_machine_report,
        outputs.machine.out,
    )

    return [info]

def lint_standardrb_aspect(
        binary,
        configs,
        rule_kinds = ["rb_binary", "rb_library", "rb_test"],
        filegroup_tags = ["ruby", "lint-with-standardrb"],
        args = []):
    """A factory function to create a linter aspect.

    Args:
        binary: Label of the Standard Ruby executable.
            Example: "//tools/lint:standardrb" or "@bundle//bin:standardrb"
        configs: Label or list of Labels of Standard Ruby config file(s).
            Example: ["//:standard.yml"] or "//:standard.yml"
        rule_kinds: list of rule kinds to visit.
            See https://bazel.build/query/language#kind
        filegroup_tags: list of filegroup tags. Filegroups with these tags
            will be visited by the aspect in addition to Ruby rule kinds.
        args: additional command-line arguments to pass to Standard Ruby.
    """

    # syntax-sugar: allow a single config file in addition to a list
    if type(configs) == "string":
        configs = [configs]

    return aspect(
        implementation = _standardrb_aspect_impl,
        attrs = patcher_attrs | {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_standardrb": attr.label(
                default = binary,
                allow_files = True,
                executable = True,
                cfg = "exec",
            ),
            "_config_files": attr.label_list(
                default = configs,
                allow_files = True,
            ),
            "_filegroup_tags": attr.string_list(
                default = filegroup_tags,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
        toolchains = [OPTIONAL_SARIF_PARSER_TOOLCHAIN],
    )
