"""API for declaring a clippy lint aspect that visits rust_{binary|library|test} rules.

Typical usage:

The rules_lint Clippy integration uses the clippy binary from your configured Rust toolchain.

First, create a clippy configuration file. We'll assume you've created it in `//:.clippy.toml`.
The file name must be suffixed by either `.clippy.toml` or `clippy.toml`, otherwise clippy will silently ignore it.

Finally, create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint_rust//:clippy.bzl", "lint_clippy_aspect")

clippy = lint_clippy_aspect(
    config = Label("//:.clippy.toml"),
    # Any clippy flags as needed like "-DWarnings".
    clippy_flags = ["-Dwarnings"],
)
```

Now your targets will be linted with clippy.
Only targets built with the `rules_rust` that `rules_rs` provides are linted. The aspect skips any other Rust target,
and a `lint_test` on one fails rather than passing with nothing checked.
If you wish a target to be excluded from linting, you can give them the `noclippy` tag.
If you wish a clippy lint exception to fail the build, please enable the `--@rules_lint//lint:fail_on_violation` flag.

Please note that the aspect will propagate to all transitive Rust dependencies of your
`rust_library`, `rust_binary`, and `rust_test` targets.

Please watch issue https://github.com/aspect-build/rules_lint/issues/385 for updates on this behavior.
"""

load("@rules_lint//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OUTFILE_FORMAT", "filter_srcs", "noop_lint_action", "output_files", "patch_and_output_files", "should_visit")
load("@rules_lint//lint/private:patcher_action.bzl", "patcher_attrs", "run_patcher")
load("@rules_rust//rust:defs.bzl", "rust_clippy_action")
load("@rules_rust//rust:rust_common.bzl", "CrateInfo", "TestCrateInfo")

_MNEMONIC = "AspectRulesLintClippy"

ClippyInfo = provider(
    doc = "Internal clippy lint results.",
    fields = {
        "raw_exit_codes": "depset of raw clippy process exit code files for this target and its dependencies",
    },
)

def _parse_clippy_output_into_files(ctx, outputs, raw_clippy_output, raw_clippy_exit_code, dep_raw_exit_codes, fail_on_violation):
    args = ctx.actions.args()
    args.add(raw_clippy_output)
    args.add(raw_clippy_exit_code)
    args.add(outputs.human.out)
    outs = [
        outputs.human.out,
    ]
    command = """
raw_exit_code=$(cat "$2")
if [[ -s "$1" ]]; then
    cp "$1" "$3"
    if [[ "${raw_exit_code}" == 0 ]]; then
        exit_code=1
    else
        exit_code="${raw_exit_code}"
    fi
else
    touch "$3"
    exit_code="${raw_exit_code}"
fi
"""

    dep_exit_code_start = 4 if fail_on_violation else 6
    command += """
for dep_exit_code_file in "${@:%s}"; do
    dep_exit_code=$(cat "${dep_exit_code_file}")
    if [[ "${dep_exit_code}" != 0 ]]; then
        exit_code="${dep_exit_code}"
    fi
done
""" % dep_exit_code_start

    if fail_on_violation:
        command += """
if [[ "${exit_code}" != 0 ]]; then
    cat "$3" >&2
    exit "${exit_code}"
fi
"""
    else:
        command += """
echo "${exit_code}" > $4
echo "${exit_code}" > $5
"""
        args.add(outputs.human.exit_code)
        args.add(outputs.machine.exit_code)
        outs.append(outputs.human.exit_code)
        outs.append(outputs.machine.exit_code)

    args.add_all(dep_raw_exit_codes)

    ctx.actions.run_shell(
        command = command,
        arguments = [args],
        inputs = depset([
            raw_clippy_output,
            raw_clippy_exit_code,
        ], transitive = [dep_raw_exit_codes]),
        outputs = outs,
    )

_CLIPPY_SKIP_TAG = "noclippy"

def _has_skip_tag(rule):
    return _CLIPPY_SKIP_TAG in rule.attr.tags

def _dep_raw_exit_code_depsets(rule):
    if hasattr(rule.attr, "deps"):
        return [
            dep[ClippyInfo].raw_exit_codes
            for dep in rule.attr.deps
            if ClippyInfo in dep
        ]
    return []

# buildifier: disable=function-docstring
def _clippy_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    rust_toolchain = ctx.toolchains[Label("@rules_rust//rust:toolchain_type")]
    clippy_bin = rust_toolchain.clippy_driver

    files_to_lint = filter_srcs(ctx.rule)

    # Declare outputs with sibling = crate_info.output when available, so they're placed in the same directory
    # structure that rustc expects. This is required because rust_clippy_action sets --out-dir based on
    # crate_info.output and rustc needs to write .d files to that directory
    crate_info = rust_clippy_action.get_clippy_ready_crate_info(target, ctx)
    sibling = crate_info.output if crate_info else None

    patch_file = None
    if ctx.attr._options[LintOptionsInfo].fix:
        outputs, info = patch_and_output_files(_MNEMONIC, target, ctx, sibling)
        patch_file = getattr(outputs, "patch", None)
    else:
        outputs, info = output_files(_MNEMONIC, target, ctx, sibling)

    if len(files_to_lint) == 0 or not crate_info or _has_skip_tag(ctx.rule):
        noop_lint_action(ctx, outputs)
        return [
            info,
            ClippyInfo(raw_exit_codes = depset(transitive = _dep_raw_exit_code_depsets(ctx.rule))),
        ]

    clippy_flags = [
        # If we don't pass any clippy options, rules_rust will (rightly) default to -Dwarnings, which turns all warnings into errors.
        # They do this to force Bazel to re-run targets on failures.
        # However, we don't need to do that because we keep track of output files and exit codes separately.
        "-Wwarnings",
    ] + ctx.attr._clippy_flags + ctx.attr._args

    fail_on_violation = ctx.attr._options[LintOptionsInfo].fail_on_violation

    raw_output = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_clippy_output_human"), sibling = sibling)
    raw_exit_code = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_clippy_exit_code"), sibling = sibling)
    raw_rustc_json_diagnostics = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "rustc_json_diagnostics"), sibling = sibling)

    rust_clippy_action.action(
        ctx,
        clippy_executable = clippy_bin,
        crate_info = crate_info,
        config = ctx.file._config_file,
        output = raw_output,
        captured_exit_code_file = raw_exit_code,
        cap_at_warnings = False,
        extra_clippy_flags = clippy_flags,
        clippy_diagnostics_file = raw_rustc_json_diagnostics,
    )

    dep_raw_exit_code_depsets = _dep_raw_exit_code_depsets(ctx.rule)
    _parse_clippy_output_into_files(ctx, outputs, raw_output, raw_exit_code, depset(transitive = dep_raw_exit_code_depsets), fail_on_violation)
    _parse_to_sarif_action(ctx, raw_rustc_json_diagnostics, outputs.machine.out)

    if patch_file != None:
        _run_patcher(ctx, files_to_lint, raw_rustc_json_diagnostics, patch_file)

    return [
        info,
        ClippyInfo(raw_exit_codes = depset([raw_exit_code], transitive = dep_raw_exit_code_depsets)),
    ]

def _run_patcher(ctx, srcs, rustc_diagnostics_file, patch_file):
    args = [
        "patch",
        # This path is relative to the execroot, we must relativize it to the bindir.
        "../../../" + rustc_diagnostics_file.path,
    ]

    # Use ctx.actions.symlink instead of copy_files_to_bin_actions so that the
    # aspect creates the same action type (SymlinkAction) as rules_rust does when
    # a target has generated inputs. rules_rust symlinks all source files to the
    # bin directory in that case, and Bazel resolves shareable action conflicts
    # only when the action keys match — which requires identical action types.
    # See: https://github.com/bazelbuild/rules_rust/blob/74bd3d15f33c6133c84bf4348225cbc7ac206f51/rust/private/utils.bzl#L857
    srcs_inputs = []
    for src in srcs:
        if src.is_source:
            # Strip the package prefix to get the path relative to the package,
            # so declare_file places the output at bazel-out/.../bin/<package>/<relative>.
            package_prefix = ctx.label.package + "/"
            relative_path = src.short_path[len(package_prefix):] if src.short_path.startswith(package_prefix) else src.short_path
            bin_file = ctx.actions.declare_file(relative_path)
            ctx.actions.symlink(output = bin_file, target_file = src)
            srcs_inputs.append(bin_file)
        else:
            srcs_inputs.append(src)

    run_patcher(
        ctx,
        ctx.executable,
        inputs = [rustc_diagnostics_file] + srcs_inputs,
        args = args,
        tools = [ctx.executable._rustc_diagnostic_parser],
        files_to_diff = [s.path for s in srcs],
        patch_out = patch_file,
        patch_cfg_env = {"BAZEL_BINDIR": ctx.bin_dir.path},
        env = {},
        mnemonic = _MNEMONIC,
        progress_message = "Applying Clippy fixes to %{label}",
    )

def _parse_to_sarif_action(ctx, rustc_diagnostics_file, sarif_output):
    args = [
        "sarif",
        rustc_diagnostics_file.path,
        sarif_output.path,
    ]

    ctx.actions.run(
        executable = ctx.executable._rustc_diagnostic_parser,
        arguments = args,
        inputs = [rustc_diagnostics_file],
        outputs = [sarif_output],
        # Must be set for js_binary to run.
        # Ref: https://github.com/aspect-build/rules_js/tree/dbb5af0d2a9a2bb50e4cf4a96dbc582b27567155?tab=readme-ov-file#running-nodejs-programs
        env = {
            "BAZEL_BINDIR": ".",
        },
    )

DEFAULT_RULE_KINDS = ["rust_binary", "rust_library", "rust_shared_library", "rust_test"]

def lint_clippy_aspect(config, rule_kinds = DEFAULT_RULE_KINDS, clippy_flags = [], args = []):
    """A factory function to create a linter aspect.

    The Clippy binary will be read from the Rust toolchain.

    Args:
        config (File): Label of the desired Clippy configuration file to use. Reference: https://doc.rust-lang.org/clippy/configuration.html
        rule_kinds (List[str]): List of rule kinds to lint. Defaults to {default_rule_kinds}.
        clippy_flags (List[str]): Extra clippy/rustc lint flags (e.g. `-Dwarnings`, `-Aclippy::style`).
        args (List[str]): Additional options to pass to Clippy.
    """.format(default_rule_kinds = DEFAULT_RULE_KINDS)
    attrs = {
        "_options": attr.label(
            default = "@rules_lint//lint:options",
            providers = [LintOptionsInfo],
        ),
        "_config_file": attr.label(
            default = config,
            allow_single_file = True,
        ),
        "_rule_kinds": attr.string_list(
            default = rule_kinds,
        ),
        "_clippy_flags": attr.string_list(
            default = clippy_flags,
        ),
        "_args": attr.string_list(
            default = args,
        ),
        "_rustc_sarif_parser": attr.label(
            doc = """A binary that can convert JSON rustc diagnostics into SARIF.

Note that rustc diagnostics are different from cargo diagnostics, which is what common rust implementations like sarif-rs use.
In particular, cargo diagnostics _may contain_ rustc diagnostics, but they don't have to.

References:
- Rustc diagnostic format: https://doc.rust-lang.org/beta/rustc/json.html#diagnostics
""",
            default = Label("//:cli"),
            executable = True,
            cfg = "exec",
        ),
        "_rustc_diagnostic_parser": attr.label(
            doc = """A binary that can convert JSON rustc diagnostics into SARIF.

Note that rustc diagnostics are different from cargo diagnostics, which is what common rust implementations like sarif-rs use.
In particular, cargo diagnostics _may contain_ rustc diagnostics, but they don't have to.

References:
- Rustc diagnostic format: https://doc.rust-lang.org/beta/rustc/json.html#diagnostics
""",
            default = Label("//:cli"),
            executable = True,
            cfg = "exec",
        ),
    }
    return aspect(
        fragments = ["cpp"],
        attr_aspects = ["deps"],
        implementation = _clippy_aspect_impl,
        attrs = patcher_attrs | attrs,
        # A target not built by rules_rs carries a CrateInfo this module cannot read, so skip
        # it rather than report it clean. Either provider qualifies: static and shared
        # libraries advertise only the test one.
        # https://github.com/hermeticbuild/rules_rust/blob/d11dcf615d6eddeb48d524d464563ca06c3b2a98/rust/private/rust.bzl#L1278-L1281
        required_providers = [
            [CrateInfo],
            [TestCrateInfo],
        ],
        toolchains =
            [
                Label("@rules_rust//rust:toolchain_type"),
                "@bazel_tools//tools/cpp:toolchain_type",
            ],
    )
