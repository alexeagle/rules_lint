load("@rules_lint//format:defs.bzl", "format_multirun")
load("@rules_java//java:defs.bzl", "java_binary")

package(default_visibility = ["//:__subpackages__"])

java_binary(
    name = "scalafmt",
    data = ["//:.scalafmt.conf"],
    main_class = "org.scalafmt.cli.Cli",
    runtime_deps = ["@maven//:org_scalameta_scalafmt_cli_2_13"],
)

format_multirun(
    name = "format",
    scala = ":scalafmt",
    visibility = ["//:__subpackages__"],
)
