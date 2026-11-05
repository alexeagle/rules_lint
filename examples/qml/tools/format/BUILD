load("@rules_lint//format:defs.bzl", "format_multirun")
load("@rules_python//python:defs.bzl", "py_binary")

package(default_visibility = ["//:__subpackages__"])

# Used instead of py_console_script_binary to avoid an extra error log
py_binary(
    name = "qmlformat",
    srcs = ["qmlformat_wrapper.py"],
    main = "qmlformat_wrapper.py",
    deps = [
        "@pip//pyside6_essentials",
    ],
)

format_multirun(
    name = "format",
    qml = ":qmlformat",
    visibility = ["//:__subpackages__"],
)
