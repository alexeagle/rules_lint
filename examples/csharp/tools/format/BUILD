load("@rules_lint//format:defs.bzl", "format_multirun")

package(default_visibility = ["//:__subpackages__"])

format_multirun(
    name = "format",
    csharp = "@paket.main//csharpier/tools:csharpier",
    visibility = ["//:__subpackages__"],
)
