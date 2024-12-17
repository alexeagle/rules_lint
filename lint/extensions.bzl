"Adapt repository rule macros to bzlmod"

load("checkstyle.bzl", "fetch_checkstyle")
load("ktlint.bzl", "fetch_ktlint")
load("pmd.bzl", "fetch_pmd")

def _jvm_dependencies_impl(_ctx):
    fetch_checkstyle()
    fetch_ktlint()
    fetch_pmd()

jvm_dependencies = module_extension(
    implementation = _jvm_dependencies_impl,
)
