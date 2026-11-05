"""Define fetches needed for tools"""

load("@rules_lint//tools/toolchains:sarif_parser_toolchain.bzl", "SARIF_PARSER_PLATFORMS", "sarif_parser_platform_repo", "sarif_parser_toolchains_repo")

# buildifier: disable=bzl-visibility
load("@bazel_lib//lib/private:source_toolchains_repo.bzl", "source_toolchains_repo")
load("//tools:version.bzl", "IS_PRERELEASE")

DEFAULT_SARIF_PARSER_REPOSITORY = "sarif_parser"

def register_sarif_parser_toolchains(name = DEFAULT_SARIF_PARSER_REPOSITORY, register = True):
    """Registers sarif_parser toolchain and repositories

    Args:
        name: override the prefix for the generated toolchain repositories
        register: whether to call through to native.register_toolchains.
            Should be True for WORKSPACE users, but false when used under bzlmod extension
    """
    if IS_PRERELEASE:
        # Bzlmod users only: build the sarif_parser tools from source when using non-release version
        # For WORKSPACE it's too difficult to setup all our transitive go_repository deps
        if not register:
            source_toolchains_repo(
                name = "%s_toolchains" % name,
                toolchain_type = "@rules_lint//tools/toolchains:sarif_parser_toolchain_type",
                toolchain_rule_load_from = "@rules_lint//tools/toolchains:sarif_parser_toolchain.bzl",
                toolchain_rule = "sarif_parser_toolchain",
                binary = "@rules_lint//tools/sarif/cmd/sarif",
            )
        return

    for [platform, _] in SARIF_PARSER_PLATFORMS.items():
        sarif_parser_platform_repo(
            name = "%s_%s" % (name, platform),
            platform = platform,
        )
        if register:
            native.register_toolchains("@%s_toolchains//:%s_toolchain" % (name, platform))

    sarif_parser_toolchains_repo(
        name = "%s_toolchains" % name,
        user_repository_name = name,
    )
