"""BUILD definition for the formatter binary"""

load("@rules_lint//format:defs.bzl", "format_multirun")

package(default_visibility = ["//:__subpackages__"])

format_multirun(
    name = "format",
    protocol_buffer = "//tools/lint:buf",
    visibility = ["//:__subpackages__"],
)
