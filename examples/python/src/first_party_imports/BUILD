load("@rules_python//python:defs.bzl", "py_library")

exports_files(["ruff.toml"])

# Ruff's isort rules (I001) only classify `first_party_lib` as first-party if it can see the
# module on disk, which requires the transitive sources of `deps` to be inputs of the ruff action.
# Without that, it is treated as third-party and the import block below is reported as unsorted.
py_library(
    name = "uses_first_party",
    srcs = ["uses_first_party.py"],
    visibility = ["//test:__pkg__"],
    deps = ["//first_party_lib:helper"],
)
