"""Support repos that aren't on bazel central registry.

Needed until Bazel 7 allows MODULE.bazel to directly call repository rules.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", _http_archive = "http_archive", _http_file = "http_file", _http_jar = "http_jar")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def http_archive(**kwargs):
    maybe(_http_archive, **kwargs)

def http_file(**kwargs):
    maybe(_http_file, **kwargs)

def http_jar(**kwargs):
    maybe(_http_jar, **kwargs)

def rules_lint_dependencies():
    http_archive(
        name = "rules_multirun",
        sha256 = "0e124567fa85287874eff33a791c3bbdcc5343329a56faa828ef624380d4607c",
        url = "https://github.com/keith/rules_multirun/releases/download/0.9.0/rules_multirun.0.9.0.tar.gz",
    )

    http_archive(
        name = "rules_multitool",
        sha256 = "557b71b7d8d9975afc7fc2381c4c0e4220d43a581fb019217ca0a040d6cbebff",
        strip_prefix = "rules_multitool-0.6.0",
        url = "https://github.com/theoremlp/rules_multitool/releases/download/v0.6.0/rules_multitool-0.6.0.tar.gz",
    )

    # Transitive of rules_multitool, included here for convenience
    # Note that many WORKSPACE users will get an earlier (and incompatible) version from some other *_dependencies() helper
    http_archive(
        name = "bazel_features",
        sha256 = "06f02b97b6badb3227df2141a4b4622272cdcd2951526f40a888ab5f43897f14",
        strip_prefix = "bazel_features-1.9.0",
        url = "https://github.com/bazel-contrib/bazel_features/releases/download/v1.9.0/bazel_features-v1.9.0.tar.gz",
    )

def fetch_java_format():
    http_jar(
        name = "google-java-format",
        sha256 = "33068bbbdce1099982ec1171f5e202898eb35f2919cf486141e439fc6e3a4203",
        url = "https://github.com/google/google-java-format/releases/download/v1.17.0/google-java-format-1.17.0-all-deps.jar",
    )

def fetch_ktfmt():
    http_jar(
        name = "ktfmt",
        integrity = "sha256-l/x/vRlNAan6RdgUfAVSQDAD1VusSridhNe7TV4/SN4=",
        url = "https://repo1.maven.org/maven2/com/facebook/ktfmt/0.46/ktfmt-0.46-jar-with-dependencies.jar",
    )

def _jvm_dependencies_impl(_ctx):
    fetch_ktfmt()
    fetch_java_format()

jvm_dependencies = module_extension(
    implementation = _jvm_dependencies_impl,
)

def fetch_swiftformat():
    # TODO: after https://github.com/bazelbuild/rules_swift/issues/864 we should only fetch for host
    http_archive(
        name = "swiftformat",
        build_file_content = "filegroup(name = \"swiftformat\", srcs=[\"swiftformat_linux\"], visibility=[\"//visibility:public\"])",
        patch_cmds = ["chmod u+x swiftformat_linux"],
        sha256 = "f62813980c2848cb1941f1456a2a06251c2e2323183623760922058b98c70745",
        url = "https://github.com/nicklockwood/SwiftFormat/releases/download/0.49.17/swiftformat_linux.zip",
    )

    http_archive(
        name = "swiftformat_mac",
        build_file_content = "filegroup(name = \"swiftformat_mac\", srcs=[\"swiftformat\"], visibility=[\"//visibility:public\"])",
        patch_cmds = [
            # On MacOS, `xattr -c` clears the "Unknown developer" warning when executing a fetched binary
            "if command -v xattr > /dev/null; then xattr -c swiftformat; fi",
            "chmod u+x swiftformat",
        ],
        sha256 = "978eaffdc3716bbc0859aecee0d83875cf3ab8d8725779448f0035309d9ad9f3",
        url = "https://github.com/nicklockwood/SwiftFormat/releases/download/0.49.17/swiftformat.zip",
    )

def _swift_dependencies_impl(_ctx):
    fetch_swiftformat()

swift_dependencies = module_extension(
    implementation = _swift_dependencies_impl,
)
