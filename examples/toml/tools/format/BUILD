load("@rules_lint//format:defs.bzl", "format_multirun")
load("@bazel_lib//lib:expand_template.bzl", "expand_template")

package(default_visibility = ["//:__subpackages__"])

genrule(
    name = "taplo",
    srcs = select({
        "@platforms//os:linux": ["@taplo//file"],
        "@platforms//os:macos": ["@taplo_mac//file"],
    }),
    outs = ["taplo_bin"],
    cmd = "gunzip -c $< > $@",
    executable = True,
)

expand_template(
    name = "taplo_wrapper",
    out = "taplo_wrapper.sh",
    data = [":taplo_bin"],
    is_executable = True,
    substitutions = {"{taplo_bin}": "$(execpath :taplo_bin)"},
    template = [
        "#!/bin/sh",
        'exec env RUST_LOG=warn "./{taplo_bin}" "$@"',
    ],
)

format_multirun(
    name = "format",
    toml = ":taplo_wrapper",
    visibility = ["//:__subpackages__"],
)
