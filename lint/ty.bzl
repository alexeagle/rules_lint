"""API for declaring a Ty lint aspect that visits py_{binary|library|test} rules.

Typical usage:

Ty is provided as a built-in tool by rules_lint. To use the built-in version,
create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:ty.bzl", "lint_ty_aspect")

ty = lint_ty_aspect(
    binary = Label("@rules_lint//lint:ty_bin"),
    config = Label("//:ty.toml"),
)
```
"""

load("@rules_python//python:defs.bzl", "PyInfo")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "parse_to_sarif_action", "should_visit")

_MNEMONIC = "AspectRulesLintTy"

def ty_action(ctx, executable, srcs, transitive_srcs, config, stdout, exit_code = None, env = {}, extra_search_paths = [], color = True, args = []):
    """Run ty as an action under Bazel.

    ty supports persistent configuration files at both the project- and user-level
    as documented here: https://docs.astral.sh/ty/configuration/

    Note: all config files are passed to the action.
    This means that a change to any config file invalidates the action cache entries for ALL
    ty actions.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the ty program
        srcs: python files to be linted
        transitive_srcs: depset of transitive Python sources from dependencies
        config: labels of ty config files (pyproject.toml, ty.toml)
        stdout: output file of linter results to generate
        exit_code: output file to write the exit code.
            If None, then fail the build when ty exits non-zero.
            https://docs.astral.sh/ty/reference/exit-codes/
        env: environment variables for ty
        extra_search_paths: list of paths to add as --extra-search-path for third-party module resolution
        color: whether to enable color output (--color always) or disable it (--color never)
        args: additional command-line options
    """
    inputs = depset(srcs + config, transitive = [transitive_srcs])
    outputs = [stdout]

    # Wire command-line options, see
    # `ty help check` to see available options
    action_args = ctx.actions.args()

    # Enable verbose output if debug mode is enabled
    if ctx.attr._options[LintOptionsInfo].debug:
        action_args.add("--vvv")

    action_args.add_all(args)

    # Add all source files to be linted
    action_args.add_all(srcs)

    # Add config file flags based on the config file type
    for config_file in config:
        if config_file.basename == "pyproject.toml":
            # For pyproject.toml, pass the directory with --project
            action_args.add("--project", config_file.dirname)
        else:
            # For ty.toml or other config files, pass the full path with --config-file
            action_args.add("--config-file", config_file.path)

    # In cases where a type can be found in both a stub and "normal" code, make sure the stub is preferred.
    # See https://github.com/astral-sh/ty/issues/1967
    stub_search_paths = []
    code_search_paths = []

    for p in extra_search_paths:
        if "_types_" in p or "_stubs" in p:
            stub_search_paths.append(p)
        else:
            code_search_paths.append(p)

    # Pass the candidate search paths in a Bazel-managed parameter file so the
    # shell command stays constant-size. Some candidates may not exist, so the
    # command filters them into the parameter file consumed by ty.
    search_path_args = ctx.actions.args()
    search_path_args.add_all(stub_search_paths + code_search_paths)
    search_path_args.set_param_file_format("multiline")
    search_path_args.use_param_file("%s", use_always = True)

    extra_search_path_script = """readonly SEARCH_PATHS_FILE="$1"
shift

readonly PARAM_FILE="$(mktemp)"
while IFS= read -r path; do
  if [ -d "$path" ]; then
    printf '%s\n' "--extra-search-path" "$path" >> "$PARAM_FILE"
  fi
done < "$SEARCH_PATHS_FILE"
"""

    color_flag = "--color always" if color else "--color never"
    command = """
{extra_search_path_script}
readonly TMP_OUT=$(mktemp)

{ty} check --force-exclude {color_flag} @"$PARAM_FILE" $@ > "$TMP_OUT" 2>&1
RET=$?

if [ "$RET" -eq 0 ]; then
    touch {stdout}
else
    cp "$TMP_OUT" {stdout}
fi
"""

    if exit_code:
        outputs.append(exit_code)
        command += """
echo "$RET" > {exit_code}
"""
    else:
        command += """
if [ "$RET" -ne 0 ]; then
    cat "$TMP_OUT" >&2
    exit "$RET"
fi
"""

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        command = command.format(
            ty = executable.path,
            stdout = stdout.path,
            exit_code = exit_code.path if exit_code else "",
            extra_search_path_script = extra_search_path_script,
            color_flag = color_flag,
        ),
        arguments = [search_path_args, action_args],
        mnemonic = _MNEMONIC,
        env = env,
        progress_message = "Linting %{label} with ty",
        tools = [executable],
    )

def _resolve_import_path(import_path, workspace_name, bin_dir_path):
    """Map a PyInfo import path to the correct execroot-relative search path.

    Workspace-internal paths start with the workspace name (e.g. "_main/pkg/src")
    and live directly under the execroot — they must NOT be prefixed with "external/".
    if they're generated, then it will be relative to bazel bin dir
    External paths (pip packages) live under "external/" in the execroot.

    Args:
        import_path: an entry from PyInfo.imports
        workspace_name: ctx.workspace_name (e.g. "_main")
        bin_dir_path: ctx.bin_dir.path, used for generated file path

    Returns:
        The corrected path string list (some of them might not exist)
    """
    if import_path == workspace_name or import_path == ".":
        return [bin_dir_path]
    if import_path.startswith(workspace_name + "/"):
        rel = import_path[len(workspace_name) + 1:]
        return [rel, bin_dir_path + "/" + rel]
    external_rel = "external/" + import_path
    return [external_rel, bin_dir_path + "/" + external_rel]

# buildifier: disable=function-docstring
def _ty_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds, ctx.attr._filegroup_tags):
        return []

    # Collect transitive sources from dependencies using the standard PyInfo provider.
    transitive_sources = []

    # Collect import paths from PyInfo for --extra-search-path.
    # _resolve_import_path maps each entry to the correct execroot-relative path:
    #   - pip packages get an "external/" prefix
    #   - workspace-internal paths get the workspace name stripped
    import_paths = {
        ctx.bin_dir.path: True,
    }

    # Collect from deps, pyi_deps, and srcs attributes using PyInfo:
    # - pyi_deps provides type stub dependencies for rules_python targets.
    # - When srcs contain labels to other targets (e.g., genrules that produce .py files),
    #   we need to collect their transitive sources for proper type resolution.
    for attr_name in ("deps", "pyi_deps", "srcs"):
        if hasattr(ctx.rule.attr, attr_name):
            for dep in getattr(ctx.rule.attr, attr_name):
                if PyInfo in dep:
                    transitive_sources.append(dep[PyInfo].transitive_sources)
                    transitive_sources.append(dep[PyInfo].transitive_pyi_files)
                    imports = dep[PyInfo].imports.to_list()
                    if imports:
                        for import_path in imports:
                            resolved = _resolve_import_path(import_path, ctx.workspace_name, ctx.bin_dir.path)
                            for e in resolved:
                                import_paths[e] = True
                    elif dep.label.workspace_root:
                        import_paths[dep.label.workspace_root] = True
                        import_paths[ctx.bin_dir.path + "/" + dep.label.workspace_root] = True

    files_to_lint = filter_srcs(ctx.rule)
    outputs, info = output_files(_MNEMONIC, target, ctx)

    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    color_env = {"FORCE_COLOR": "1"} if ctx.attr._options[LintOptionsInfo].color else {}

    # Pass transitive sources to ty_action so ty can resolve imports from dependencies
    transitive_srcs_depset = depset(transitive = transitive_sources)
    extra_search_paths = import_paths.keys()
    ty_action(ctx, ctx.executable._ty, files_to_lint, transitive_srcs_depset, ctx.files._config_file, outputs.human.out, outputs.human.exit_code, env = color_env, extra_search_paths = extra_search_paths, color = ctx.attr._options[LintOptionsInfo].color, args = ctx.attr._args)

    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    ty_action(ctx, ctx.executable._ty, files_to_lint, transitive_srcs_depset, ctx.files._config_file, raw_machine_report, outputs.machine.exit_code, extra_search_paths = extra_search_paths, color = False, args = ctx.attr._args)

    # Ideally we'd just use {"TY_OUTPUT_FORMAT": "sarif"} however it prints absolute paths; see https://github.com/astral-sh/ruff/issues/14985
    # This issue should also be resolved when the issue from ruff is fixed.
    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)

    return [info]

def lint_ty_aspect(binary, config, rule_kinds = ["py_binary", "py_library", "py_test"], filegroup_tags = ["python", "lint-with-ty"], args = []):
    """A factory function to create a linter aspect.

    Attrs:
        binary: a ty executable
        configs: ty config file(s) (`pyproject.toml`, `ty.toml`)
        rule_kinds: which [kinds](https://bazel.build/query/language#kind) of rules should be visited by the aspect
        filegroup_tags: filegroups tagged with these tags will be visited by the aspect in addition to Python rule kinds
        args: additional command-line options to pass to ty
    """

    return aspect(
        implementation = _ty_aspect_impl,
        # Propagate the aspect to dependencies so they are also linted.
        # Transitive sources for type resolution are obtained via PyInfo provider.
        attr_aspects = ["deps"],
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_ty": attr.label(
                default = binary,
                allow_files = True,
                executable = True,
                cfg = "exec",
            ),
            "_config_file": attr.label(
                default = config,
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
