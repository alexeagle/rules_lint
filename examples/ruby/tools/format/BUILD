load("@rules_lint//format:defs.bzl", "format_multirun")
load("@rules_ruby//ruby:defs.bzl", "rb_binary")

package(default_visibility = ["//:__subpackages__"])

exports_files([
    "Gemfile",
    "Gemfile.lock",
    "syntax-tree-cli.patch",
    "rules-ruby-gem-patches.patch",
])

rb_binary(
    name = "stree",
    main = "@stree_bundle//bin:stree",
    deps = ["@stree_bundle"],
)

format_multirun(
    name = "format",
    ruby = ":stree",
)
