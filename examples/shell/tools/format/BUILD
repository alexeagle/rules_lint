"""BUILD definition for the formatter binary"""

load("@rules_lint//format:defs.bzl", "format_multirun")

package(default_visibility = ["//:__subpackages__"])

format_multirun(
    name = "format",
    shell = "@rules_lint//format:shfmt",
    visibility = ["//:__subpackages__"],
)
