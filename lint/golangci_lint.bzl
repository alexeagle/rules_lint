"""API for declaring a golangci-lint lint aspect that visits go_{library,binary,test} rules.

Typical usage in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:golangci_lint.bzl", "lint_golangci_lint_aspect")

golangci_lint = lint_golangci_lint_aspect(
    binary = Label("@rules_lint//lint:golangci_lint_bin"),
    config = Label("//:.golangci.yml"),
)
```

This aspect is hermetic, per-package, and remote-cache friendly. It reuses
rules_go's `go_pkg_info_aspect` to obtain each package's pre-computed metadata
(`.pkg.json`), transitive export data (`.x`), and stdlib archives, then runs the
real golangci-lint binary against a static, file-reading `GOPACKAGESDRIVER`
(`//lint/private/gopackagesdriver_static`). No bazel-in-bazel, no network, no
shared module cache. Requires rules_go >= 0.61.0 for cgo test inputs.
"""

load("@io_bazel_rules_go//go/private:providers.bzl", "GoStdLib")
load("@io_bazel_rules_go//go/tools/gopackagesdriver:aspect.bzl", "GoPkgInfo", "go_pkg_info_aspect")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OUTFILE_FORMAT", "output_files", "should_visit")

_MNEMONIC = "AspectRulesLintGolangciLint"

# The rules_go Go toolchain type, used to reach the GoSDK (for GOROOT) at lint
# time. Reached via ctx.toolchains[...] because the aspect declares it in
# `toolchains` below.
_GO_TOOLCHAIN = "@io_bazel_rules_go//go:toolchain"

def golangci_lint_action(ctx, executable, driver, pkg_info, sdk, stdlib, config, stdout, sarif, exit_code = None, options = [], mnemonic = _MNEMONIC):
    """Run golangci-lint hermetically against a single Go package.

    Args:
        ctx: aspect evaluation context
        executable: the golangci-lint binary
        driver: the static GOPACKAGESDRIVER binary
        pkg_info: the GoPkgInfo provider from go_pkg_info_aspect
        sdk: the rules_go GoSDK provider (used to derive GOROOT and the go binary)
        stdlib: the rules_go GoStdLib provider (precompiled stdlib .a archives)
        config: the .golangci.yml config file
        stdout: human-readable report output file
        sarif: machine-readable (raw, pre-normalization) SARIF report output file
        exit_code: optional file capturing the exit code; if None, fail on violation
        options: extra command-line options
        mnemonic: action/output identifier; distinct for differently configured instances.

    Returns:
        nothing; declares the lint action.
    """
    json_files = pkg_info.pkg_json_files
    export_files = pkg_info.export_files

    # Transitive sources, including generated sources and cgo output trees.
    # Fact-producing analyzers must inspect dependencies on a cold cache.
    srcs = pkg_info.compiled_go_files
    stdlib_json = [pkg_info.stdlib_json_file] if pkg_info.stdlib_json_file else []

    # rules_go builds the stdlib into a single "pkg" tree exposed via
    # GoStdLib.libs, laid out as pkg/<goos>_<goarch>/<importpath>.a. The static
    # driver injects each as the ExportFile for the corresponding Standard
    # package (spike finding #1). NOTE: the GoSDK's own `libs` is empty for
    # modern (>=1.20) SDKs, which is why we read the BUILT stdlib here instead.
    stdlib_libs_list = stdlib.libs.to_list()

    # Stage all .pkg.json (target + transitive deps + stdlib) into a single dir
    # the driver can glob via GOPACKAGESDRIVER_JSON_DIR. The stdlib_json_file
    # (~294 stdlib packages in one file) MUST be included: without it the driver's
    # registry has no stdlib packages, so it can neither inject their ExportFile
    # nor resolve dependencies' stdlib imports (e.g. encoding/xml, fmt).
    stage_inputs = depset(direct = stdlib_json, transitive = [json_files])
    json_dir = ctx.actions.declare_directory(OUTFILE_FORMAT.format(label = ctx.label.name, mnemonic = mnemonic, suffix = "pkgjson.d"))
    stage_args = ctx.actions.args()
    stage_args.add(json_dir.path)
    stage_args.add_all(stage_inputs)
    ctx.actions.run_shell(
        inputs = stage_inputs,
        outputs = [json_dir],
        command = 'dir="$1"; shift; mkdir -p "$dir"; for f in "$@"; do dest="$dir/$(basename "$f")"; cp -f "$f" "$dest"; chmod u+w "$dest"; done',
        arguments = [stage_args],
        mnemonic = mnemonic + "Stage",
        progress_message = "Staging Go package metadata for %{label}",
    )

    # GOROOT is the directory containing the SDK root_file. golangci-lint shells
    # out to `go env` for its build context, so the go binary must also be on
    # PATH (at $GOROOT/bin). Dependency type info still comes from the injected
    # stdlib ExportFiles, not from compiling against GOROOT.
    goroot = sdk.root_file.dirname

    args = ctx.actions.args()
    args.add("run")
    args.add("--config", config.path)
    args.add_all(options)

    env = {
        "GOPACKAGESDRIVER": driver.path,
        "GOPACKAGESDRIVER_JSON_DIR": json_dir.path,
        "GOPACKAGESDRIVER_ROOTS": str(ctx.label),
        # The bazel placeholders in the staged JSON resolve against the sandbox
        # execroot, which the action runs in (cwd == execroot == ".").
        "GOPACKAGESDRIVER_EXECROOT": ".",
        "GOPACKAGESDRIVER_WORKSPACE": ".",
        "GOPACKAGESDRIVER_OUTPUT_BASE": ".",
        "GOFLAGS": "-mod=mod",
        "GOPROXY": "off",
        # x/tools' gcimporter has a data race when decoding export data
        # concurrently (golang/go #34895, #67725, #70015); GOMAXPROCS=1 removes
        # the common multi-core trigger of "concurrent map read and map write"
        # crashes. NOTE: this is a pragmatic mitigation, not a hard guarantee —
        # Go's preemptive scheduler can still interleave goroutines under a single
        # P — but in practice it eliminates the flake, and per-package lint actions
        # are small so the single-threaded cost is negligible. If flakes ever
        # resurface, the real fix is upstream serialization in the importer.
        "GOMAXPROCS": "1",
    }

    # GOPACKAGESDRIVER_STDLIB_PKG_DIR points at the dir that *contains* the
    # <goos>_<goarch>/ subtree of precompiled .a files. GoStdLib.libs is a single
    # tree artifact: the "pkg" directory itself (.../stdlib_/pkg). The driver
    # appends "<goos>_<goarch>/<importpath>.a" to it.
    if stdlib_libs_list:
        env["GOPACKAGESDRIVER_STDLIB_PKG_DIR"] = stdlib_libs_list[0].path

    inputs = depset(
        direct = [driver, config, sdk.root_file] + stdlib_json + stdlib_libs_list,
        transitive = [json_files, export_files, srcs, pkg_info.stdlib_cache_dir, sdk.srcs, sdk.headers, sdk.tools, sdk.libs, depset([sdk.go])],
    )

    outputs = [stdout, sarif]

    # Fixed /tmp paths share undeclared cache state between local actions.
    # Use a fresh directory per action, including when sandboxing is disabled.
    # golangci-lint also locks os.TempDir()/golangci-lint.lock, so isolate
    # TMPDIR to let independent Bazel actions run concurrently.
    cache_prologue = """cache_dir="$(mktemp -d)" || exit 1; trap 'rm -rf "$cache_dir"' EXIT; """
    cache_prologue += 'export HOME="$cache_dir" GOCACHE="$cache_dir/go" GOLANGCI_LINT_CACHE="$cache_dir/golangci" TMPDIR="$cache_dir/tmp"; mkdir -p "$TMPDIR"; '

    # GOROOT/PATH must be absolute: Go refuses to exec a `go` binary found via a
    # relative path ("cannot run executable found relative to current
    # directory"). The action runs at the execroot, so prefix with $PWD at
    # runtime. golangci-lint shells out to `go env` for its build context.
    goroot_prologue = 'export GOROOT="$PWD/' + goroot + '"; export PATH="$GOROOT/bin:$PATH"; '

    # golangci-lint resolves a *relative* --output.sarif.path against its notion
    # of the workspace root, which under Bazel sandboxing is NOT the sandbox
    # execroot (it tries to mkdir the real workspace's bazel-out → "operation not
    # permitted"). Anchor the SARIF output at an absolute $PWD path inside the
    # sandbox, then copy it to the declared Bazel output. Likewise pass the
    # package pattern "./..." after the flags. The driver ignores the pattern
    # (roots come from GOPACKAGESDRIVER_ROOTS), but the CLI requires one.
    sarif_setup = 'gl_sarif="$PWD/rules_lint_golangci.sarif"; '
    run_golangci = '"$bin" "$@" --output.sarif.path "$gl_sarif" ./... >' + stdout.path + " 2>&1"
    copy_sarif = 'cp "$gl_sarif" ' + sarif.path

    # $1 is the golangci-lint binary path; "$@" (after shift) are its args. We
    # avoid str.format here because the shell expansions $@ / $? collide with
    # format's {} fields.
    if exit_code:
        # golangci-lint exits 1 when issues are found; capture rather than fail.
        command = cache_prologue + goroot_prologue + sarif_setup + 'bin="$1"; shift; ' + run_golangci + "; echo $? >" + exit_code.path + "; " + copy_sarif
        outputs.append(exit_code)
    else:
        command = cache_prologue + goroot_prologue + sarif_setup + 'bin="$1"; shift; ' + run_golangci + "; " + copy_sarif

    run_args = ctx.actions.args()
    run_args.add(executable.path)

    ctx.actions.run_shell(
        inputs = depset(direct = [json_dir], transitive = [inputs]),
        outputs = outputs,
        command = command,
        arguments = [run_args, args],
        env = env,
        mnemonic = mnemonic,
        progress_message = "Linting %{label} with golangci-lint",
        tools = [executable, driver],
    )

def _normalize_sarif_action(ctx, raw_sarif, normalized_sarif):
    """Rewrite golangci-lint SARIF result URIs to workspace-relative paths.

    golangci-lint emits `artifactLocation.uri` values that are relative to the
    linter's CWD (the bazel execroot), reaching first-party sources via deep
    `../` traversal and external-dep sources via the bazel cache (spike finding
    #3). Neither form is portable across machines, which defeats remote-cache
    sharing of the SARIF output.

    This action canonicalizes each `uri` by keying on the `/execroot/<repo>/`
    segment that Bazel always places in the absolute path: everything after it is
    the workspace-relative path. For the main repo that yields `tools/sarif/sarif.go`;
    for a dependency it yields `external/...`, which reads as clearly non-local and
    never masquerades as a first-party path.

    Args:
        ctx: aspect evaluation context
        raw_sarif: the SARIF file produced by golangci-lint
        normalized_sarif: the rewritten, workspace-relative SARIF (machine output)
    """
    args = ctx.actions.args()
    args.add("-in", raw_sarif.path)
    args.add("-out", normalized_sarif.path)
    args.add("-label", ctx.label)
    args.add("-mnemonic", _MNEMONIC)
    ctx.actions.run(
        inputs = [raw_sarif],
        outputs = [normalized_sarif],
        executable = ctx.executable._sarif_parser,
        arguments = [args],
        mnemonic = ctx.attr._mnemonic + "Sarif",
        progress_message = "Normalizing golangci-lint SARIF URIs for %{label}",
    )

# buildifier: disable=function-docstring
def _golangci_lint_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []
    if GoPkgInfo not in target:
        return []

    pkg_info = target[GoPkgInfo]
    sdk = ctx.toolchains[_GO_TOOLCHAIN].sdk
    stdlib = ctx.attr._go_stdlib[GoStdLib]

    options = ctx.attr._options[LintOptionsInfo]
    outputs, info = output_files(ctx.attr._mnemonic, target, ctx)

    extra_options = []
    if options.color:
        extra_options.extend(["--color", "always"])

    # NOTE: golangci-lint's --fix modifies sources in place rather than emitting
    # a unified diff (unlike shellcheck's --format diff). Producing a hermetic
    # patch would require staging writable source copies and diffing; patch/fix
    # mode is intentionally not wired here. See the report / README.

    # golangci-lint writes SARIF to a path we control. Capture the raw SARIF in
    # a temp file and normalize it into the machine output.
    raw_sarif = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = ctx.attr._mnemonic, suffix = "raw_sarif"))

    golangci_lint_action(
        ctx,
        ctx.executable._golangci_lint,
        ctx.executable._driver,
        pkg_info,
        sdk,
        stdlib,
        ctx.file._config_file,
        outputs.human.out,
        raw_sarif,
        outputs.human.exit_code,
        extra_options,
        mnemonic = ctx.attr._mnemonic,
    )

    _normalize_sarif_action(ctx, raw_sarif, outputs.machine.out)

    # The machine exit code mirrors the human exit code for this single action.
    if outputs.machine.exit_code:
        ctx.actions.symlink(output = outputs.machine.exit_code, target_file = outputs.human.exit_code)

    return [info]

def lint_golangci_lint_aspect(binary, config, rule_kinds = ["go_library", "go_binary", "go_test"], mnemonic = _MNEMONIC):
    """A factory function to create a golangci-lint linter aspect.

    Attrs:
        binary: a golangci-lint executable, typically `@rules_lint//lint:golangci_lint_bin`.
        config: the `.golangci.yml` config file.
        rule_kinds: which rule kinds to visit; defaults to go_library, go_binary, go_test.
        mnemonic: action/output identifier; use a distinct value for each differently configured instance.

    Returns:
        an aspect definition.
    """
    return aspect(
        implementation = _golangci_lint_aspect_impl,
        # Reuse rules_go's per-package metadata (pkg.json, .x, stdlib).
        requires = [go_pkg_info_aspect],
        attrs = {
            "_mnemonic": attr.string(default = mnemonic),
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_golangci_lint": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_driver": attr.label(
                default = Label("//lint/private/gopackagesdriver_static:gopackagesdriver_static"),
                executable = True,
                cfg = "exec",
            ),
            "_sarif_parser": attr.label(
                default = Label("//tools/sarif/cmd/sarif"),
                executable = True,
                cfg = "exec",
            ),
            "_config_file": attr.label(
                default = config,
                allow_single_file = True,
            ),
            "_go_stdlib": attr.label(
                default = "@io_bazel_rules_go//:stdlib",
                providers = [GoStdLib],
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
        },
        toolchains = [_GO_TOOLCHAIN],
    )
