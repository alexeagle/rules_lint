"""Module extension that declares external tool archives for the PowerShell linting example."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def _repos_impl(mctx):
    http_archive(
        name = "pwsh",
        url = "https://github.com/PowerShell/PowerShell/releases/download/v7.7.0/powershell-7.7.0-linux-x64.tar.gz",
        sha256 = "c89d9c682d2c403dfe726f3df948e359675235a5bd6fab535776de69729ca0cb",
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

    return mctx.extension_metadata(reproducible = True)

repos = module_extension(
    implementation = _repos_impl,
)
