load("@rules_lint//format:defs.bzl", "format_multirun")

package(default_visibility = ["//:__subpackages__"])

format_multirun(
    name = "format",
    fsharp = "@paket.main//fantomas/tools:fantomas",
    visibility = ["//:__subpackages__"],
)
