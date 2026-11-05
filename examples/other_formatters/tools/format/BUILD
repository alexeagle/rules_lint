load("@rules_lint//format:defs.bzl", "format_multirun")
load("@npm//:prettier/package_json.bzl", prettier = "bin")
load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")

package(default_visibility = ["//:__subpackages__"])

py_console_script_binary(
    name = "djlint",
    pkg = "@pip//djlint:pkg",
)

prettier.prettier_binary(
    name = "prettier",
    data = ["//:prettierrc"],
    env = {"BAZEL_BINDIR": "."},
    fixed_args = [
        "--config=\"$$JS_BINARY__RUNFILES\"/$(rlocationpath //:prettierrc)",
        "--log-level=warn",
    ],
)

format_multirun(
    name = "format",
    cue = "@rules_lint//format:cue",
    gherkin = ":prettier",
    graphql = ":prettier",
    html_jinja = ":djlint",
    javascript = ":prettier",  # javascript includes JSON, JSON5, TypeScript, TSX, and Vue
    jsonnet = "@rules_lint//format:jsonnetfmt",
    visibility = ["//:__subpackages__"],
)
