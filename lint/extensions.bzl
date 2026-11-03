"Module extensions for use with bzlmod"

load("@bazel_features//:features.bzl", "bazel_features")

# buildifier: disable=bzl-visibility
load("@bazel_lib//lib/private:extension_utils.bzl", "extension_utils")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive", "http_file", "http_jar")
load(
    "//tools/toolchains:register.bzl",
    "DEFAULT_SARIF_PARSER_REPOSITORY",
    "register_sarif_parser_toolchains",
)
load(":vale_library.bzl", "VALE_STYLE_DATA")
load(":vale_versions.bzl", "VALE_VERSIONS")

def _public_build_file_content(line):
    return """package(default_visibility = ["//visibility:public"])\n{}\n""".format(line)

def _lint_extension_impl(mctx):
    for mod in mctx.modules:
        for r in mod.tags.cppcheck:
            # cppcheck premium behaves like the free version and does not require a license,
            # if cppcheck.cfg is removed.
            http_archive(
                name = r.linux,
                build_file_content = _public_build_file_content("""filegroup(name = "files", srcs = glob(["**"]))"""),
                integrity = "sha256-IqQ3Iofw6LoHh4YcdbN0m3tjg6utCiey7nGaOaPMv/I=",
                patch_cmds = ["rm -f cppcheck.cfg"],
                strip_prefix = "cppcheckpremium-25.8.3",
                urls = ["https://files.cppchecksolutions.com/25.8.3/ubuntu-22.04/cppcheckpremium-25.8.3-amd64.tar.gz"],
            )
            http_archive(
                name = r.macos,
                build_file_content = _public_build_file_content("""filegroup(name = "files", srcs = glob(["**"]))"""),
                integrity = "sha256-PEtm/DxKNZNJJuZE+56AZ80R22sZjZoziekAmR7FhNk=",
                patch_cmds = ["rm -f cppcheck.cfg"],
                strip_prefix = "cppcheckpremium",
                urls = ["https://files.cppchecksolutions.com/25.8.3/cppcheckpremium-25.8.3-macos-15.tar.gz"],
            )
        for r in mod.tags.pmd:
            http_archive(
                name = r.name,
                build_file_content = _public_build_file_content("\n".join([
                    """load("@rules_java//java:defs.bzl", "java_import")""",
                    """java_import(name = "{}", jars = glob(["*.jar"]))""".format(r.name),
                ])),
                integrity = "sha256-vov2j2wdZphL2WRak+Yxt4ocL0L18PhxkIL+rWdVOUA=",
                strip_prefix = "pmd-bin-7.7.0/lib",
                url = "https://github.com/pmd/pmd/releases/download/pmd_releases/7.7.0/pmd-dist-7.7.0-bin.zip",
            )
        for r in mod.tags.checkstyle:
            http_jar(
                name = r.name,
                url = "https://github.com/checkstyle/checkstyle/releases/download/checkstyle-10.17.0/checkstyle-10.17.0-all.jar",
                sha256 = "51c34d738520c1389d71998a9ab0e6dabe0d7cf262149f3e01a7294496062e42",
            )
        for r in mod.tags.ktlint:
            http_file(
                name = r.name,
                sha256 = "2e28cf46c27d38076bf63beeba0bdef6a845688d6c5dccd26505ce876094eb92",
                url = "https://github.com/pinterest/ktlint/releases/download/1.2.1/ktlint",
                executable = True,
            )
        for r in mod.tags.spotbugs:
            http_archive(
                name = r.name,
                integrity = "sha256-Z83FLM6xfq45T4/DZg8hZZzzVJCPgY5NH0Wmk1wuRCU=",
                url = "https://github.com/spotbugs/spotbugs/releases/download/4.8.6/spotbugs-4.8.6.zip",
                strip_prefix = "spotbugs-4.8.6",
                build_file_content = _public_build_file_content("\n".join([
                    """load("@rules_java//java:defs.bzl", "java_import")""",
                    """java_import(name = "jar", jars = ["lib/spotbugs.jar"])""",
                ])),
            )
        for r in mod.tags.vale:
            version = r.tag.lstrip("v")
            url = "https://github.com/errata-ai/vale/releases/download/{tag}/vale_{version}_{plat}.{ext}"

            for plat, sha256 in VALE_VERSIONS[r.tag].items():
                is_windows = plat.startswith("Windows")
                http_archive(
                    name = "{}_{}".format(r.name, plat),
                    url = url.format(
                        tag = r.tag,
                        plat = plat,
                        version = version,
                        ext = "zip" if is_windows else "tar.gz",
                    ),
                    sha256 = sha256,
                    build_file_content = """exports_files(["vale", "vale.exe"])""",
                )
        for r in mod.tags.vale_styles:
            for style_name in r.styles:
                styles = [s for s in VALE_STYLE_DATA if s["name"] == style_name]
                if not styles:
                    fail("Unknown Vale style: {}".format(style_name))
                style = styles[0]
                http_archive(
                    name = "vale_" + style["name"],
                    integrity = style["integrity"],
                    # Note: this is actually a directory, not a file
                    build_file_content = """exports_files(["{}"])""".format(style["name"]),
                    url = style["url"].format(style["version"]),
                )

tools = module_extension(
    implementation = _lint_extension_impl,
    tag_classes = {
        "cppcheck": tag_class(attrs = {"linux": attr.string(default = "cppcheck_linux"), "macos": attr.string(default = "cppcheck_macos")}),
        "spotbugs": tag_class(attrs = {"name": attr.string(default = "spotbugs")}),
        "ktlint": tag_class(attrs = {"name": attr.string(default = "com_github_pinterest_ktlint")}),
        "pmd": tag_class(attrs = {"name": attr.string(default = "net_sourceforge_pmd")}),
        "checkstyle": tag_class(attrs = {"name": attr.string(default = "com_puppycrawl_tools_checkstyle")}),
        "vale": tag_class(attrs = {"name": attr.string(default = "vale"), "tag": attr.string(default = VALE_VERSIONS.keys()[0])}),
        "vale_styles": tag_class(attrs = {"styles": attr.string_list()}),
    },
)

def _toolchains_extension_impl(mctx):
    extension_utils.toolchain_repos_bfs(
        mctx = mctx,
        get_tag_fn = lambda tags: tags.sarif_parser,
        toolchain_name = "sarif_parser",
        toolchain_repos_fn = lambda name, version: register_sarif_parser_toolchains(name = name, register = False),
        get_version_fn = lambda attr: None,
    )

    if bazel_features.external_deps.extension_metadata_has_reproducible:
        return mctx.extension_metadata(reproducible = True)
    return mctx.extension_metadata()

toolchains = module_extension(
    implementation = _toolchains_extension_impl,
    tag_classes = {
        "sarif_parser": tag_class(attrs = {"name": attr.string(default = DEFAULT_SARIF_PARSER_REPOSITORY)}),
    },
)
