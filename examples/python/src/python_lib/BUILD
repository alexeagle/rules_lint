load("@rules_python//python:defs.bzl", "py_library")

package(default_visibility = ["//visibility:public"])

# The `imports = ["."]` adds this package directory to the Python path, so
# dependents can `from dependency import greet` instead of
# `from python_lib.dependency import greet`.  This is common with
# Gazelle-managed src/ layouts and exercises the workspace-internal import
# path resolution in the ty aspect (https://github.com/aspect-build/rules_lint/issues/728).
py_library(
    name = "py_dependency",
    srcs = ["dependency.py"],
    imports = ["."],
    pyi_srcs = ["stub.pyi"],
)
