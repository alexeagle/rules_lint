"""Module extension that declares external tool archives for the PowerShell linting example."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def _repos_impl(_mctx):
    http_archive(
        name = "pwsh",
        url = "https://github.com/PowerShell/PowerShell/releases/download/v7.6.9/powershell-7.6.9-linux-x64.tar.gz",
        sha256 = "1da6d6d6035d651f20e70ddee7c4c15ac6ab8b9fb40ee92240d91263f28a884b",
        build_file_content = """exports_files(["pwsh"])""",
        patch_cmds = ["chmod +x pwsh"],
    )
    http_archive(
        name = "psscriptanalyzer",
        url = "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/1.25.0",
        sha256 = "14e634c828eb98efb9f40b2918ba90f139ed5eccdf663a2a747736d996995d60",
        type = "zip",
        build_file_content = """
package(default_visibility = ["//visibility:public"])
filegroup(name = "files", srcs = glob(["**"]))
""",
    )
    http_archive(
        name = "converttosarif",
        url = "https://www.powershellgallery.com/api/v2/package/ConvertToSARIF/1.0.0",
        sha256 = "b1bdf60f029f12284dd78b2c2edc34705d4475079b4cb3d50d669da464bf3d35",
        type = "zip",
        build_file_content = """
package(default_visibility = ["//visibility:public"])
filegroup(name = "files", srcs = glob(["**"]))
""",
    )

repos = module_extension(
    implementation = _repos_impl,
)
