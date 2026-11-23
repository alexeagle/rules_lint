load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_python//python:defs.bzl", "py_library")
load("@rules_uv//uv:pip.bzl", "pip_compile")

package(default_visibility = ["//visibility:public"])

exports_files(
    [
        ".pylintrc",
        ".flake8",
        "pyproject.toml",
    ],
    visibility = ["//visibility:public"],
)

write_file(
    name = "generated_dependency_file",
    out = "generated_dependency.py",
    content = [
        "error: int = 'str'",
        "def greet(name: str) -> str:",
        "    return f\"Hello, {name}!\"",
    ],
)

py_library(
    name = "generated_dependency",
    srcs = ["generated_dependency.py"],
    imports = ["."],
)

# Update requirements.txt by running:
# bazel run //:requirements.update
pip_compile(
    name = "requirements",
    requirements_in = "pyproject.toml",
    requirements_txt = "requirements.txt",
    universal = True,
)
