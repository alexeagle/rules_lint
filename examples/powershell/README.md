# PowerShell Linting with PSScriptAnalyzer

This example demonstrates running [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
as a Bazel lint aspect via `rules_lint`.

## Prerequisites

PSScriptAnalyzer has no Bazel ruleset, so you supply three archives via a module extension
in `tools/repositories.bzl` (bzlmod doesn't allow `http_archive` directly in `MODULE.bazel`):

- `pwsh` — [PowerShell releases](https://github.com/PowerShell/PowerShell/releases) (`linux-x64.tar.gz`)
- `psscriptanalyzer` — [PowerShell Gallery](https://www.powershellgallery.com/packages/PSScriptAnalyzer)
- `converttosarif` — [PowerShell Gallery](https://www.powershellgallery.com/packages/ConvertToSARIF)

For the sha256: download the `.nupkg` and run `sha256sum` on it (the Gallery URL redirects, so
`curl -L -o pkg.nupkg "<url>" && sha256sum pkg.nupkg`).

## Setup

See `tools/repositories.bzl` for the `http_archive` declarations and `tools/lint/linters.bzl`
for the aspect instantiation.

Key points:

- `type = "zip"` is required for Gallery packages (the redirect URL has no file extension)
- `patch_cmds = ["chmod +x pwsh"]` restores the execute bit stripped by `http_archive`
- Pass a `PSScriptAnalyzerSettings.psd1` label as `config` to customise rules (optional)

Reference the extension from `MODULE.bazel`:

```starlark
repos = use_extension("//tools:repositories.bzl", "repos")
use_repo(repos, "converttosarif", "psscriptanalyzer", "pwsh")
```

Register the aspect in `.bazelrc`:

```
build:lint --aspects=//tools/lint:linters.bzl%ps_script_analyzer
```

Opt PowerShell files into linting with a tagged filegroup (only `.ps1` and `.psm1` are linted):

```starlark
filegroup(
    name = "scripts",
    srcs = glob(["**/*.ps1"]),
    tags = ["lint-with-psscriptanalyzer"],
)
```

## Running

```bash
bazel build --config=lint --output_groups=rules_lint_human //src:all
bazel build --config=lint --output_groups=rules_lint_machine //src:all
bazel build --config=lint --@rules_lint//lint:fail_on_violation //src:all
```
