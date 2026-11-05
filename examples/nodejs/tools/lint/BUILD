"""Definition of the linter binaries

This is in its own package because it has so many loading-time symbols,
we don't want to trigger eager fetches of these for builds that don't want to run lint.
"""

load("@rules_lint//lint:vale_library.bzl", "VALE_STYLES")
load("@bazel_lib//lib:copy_to_directory.bzl", "copy_to_directory")
load("@bazel_skylib//rules:native_binary.bzl", "native_binary")
load("@npm//:eslint/package_json.bzl", eslint_bin = "bin")
load("@npm//:stylelint/package_json.bzl", stylelint_bin = "bin")

package(default_visibility = ["//:__subpackages__"])

eslint_bin.eslint_binary(name = "eslint")

stylelint_bin.stylelint_binary(name = "stylelint")

copy_to_directory(
    name = "vale_styles",
    srcs = [
        "@vale_{0}//:{0}".format(s)
        for s in VALE_STYLES
        # Restrict to subset like Google and write-good to avoid GHA cache getting huge and exhausting disk.
        # Comment this out to test that our code to fetch them is working.
        # Most users should just copy in the styles that are referenced in their .vale.ini file.
        if "oo" in s
    ],
    include_external_repositories = ["*vale_*"],
)

native_binary(
    name = "vale",
    src = select(
        {
            "@bazel_tools//src/conditions:linux_x86_64": "@vale_Linux_64-bit//:vale",
            "@bazel_tools//src/conditions:linux_aarch64": "@vale_Linux_arm64//:vale",
            "@bazel_tools//src/conditions:darwin_x86_64": "@vale_macOS_64-bit//:vale",
            "@bazel_tools//src/conditions:darwin_arm64": "@vale_macOS_arm64//:vale",
            "@bazel_tools//src/conditions:windows_x64": "@vale_Windows_64-bit//:vale.exe",
        },
    ),
    out = "vale",
)
