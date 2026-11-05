"""BUILD definition for the formatter binary"""

load("@rules_lint//format:defs.bzl", "format_multirun")

package(default_visibility = ["//:__subpackages__"])

format_multirun(
    name = "format",
    go_module = "@multitool//tools/modfmt",
    visibility = ["//:__subpackages__"],
)
