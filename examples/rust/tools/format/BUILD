"""BUILD definition for the formatter binary"""

load("@rules_lint//format:defs.bzl", "format_multirun")

package(default_visibility = ["//:__subpackages__"])

format_multirun(
    name = "format",
    # Note, older rules_rust versions may need
    # @rules_rust//tools/rustfmt:upstream_rustfmt
    # which was later deprecated in
    # https://github.com/bazelbuild/rules_rust/pull/2703
    rust = "@rules_rust//tools/upstream_wrapper:rustfmt",
    visibility = ["//:__subpackages__"],
)
