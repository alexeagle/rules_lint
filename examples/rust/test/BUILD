# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_test")
load("//test:machine_output.bzl", "machine_clippy_report")
load("//tools/lint:linters.bzl", "clippy_test")

package(default_visibility = ["//visibility:public"])

clippy_test(
    name = "clippy_ok_binary",
    srcs = ["//src:ok_binary"],
)

clippy_test(
    name = "clippy_ok_binary_with_generated_inputs",
    srcs = ["//src:ok_binary_with_generated_inputs"],
)

clippy_test(
    name = "clippy_ok_binary_with_bad_dep",
    srcs = ["//src:ok_binary_with_bad_dep"],
    expected_exit_code = 1,
)

clippy_test(
    name = "clippy_ok_binary_with_bad_noclippy_dep",
    srcs = ["//src:ok_binary_with_bad_noclippy_dep"],
)

clippy_test(
    name = "clippy_ok_test",
    srcs = ["//src:ok_test"],
    # Tests that clippy works with rust_test targets (which place
    # crate_info.output in a subdirectory like test-<hash>/).
)

clippy_test(
    name = "clippy_bad_binary",
    srcs = ["//src:bad_binary"],
    expected_exit_code = 1,
)

clippy_test(
    name = "clippy_bad_binary_noclippy",
    srcs = ["//src:bad_binary_with_noclippy"],
)

clippy_test(
    name = "clippy_bad_library",
    srcs = ["//src:bad_lib"],
    expected_exit_code = 1,
)

clippy_test(
    name = "clippy_bad_test",
    srcs = ["//src:bad_test"],
    expected_exit_code = 1,
)

clippy_test(
    name = "clippy_binary_with_warning_and_error",
    srcs = ["//src:binary_with_warning_and_error"],
    expected_exit_code = 1,
)

clippy_test(
    name = "clippy_warning_lib",
    srcs = ["//src:warning_lib"],
    expected_exit_code = 1,
)

clippy_test(
    name = "clippy_ok_binary_with_warning_dep",
    srcs = ["//src:ok_binary_with_warning_dep"],
)

machine_clippy_report(
    name = "machine_clippy_report",
    src = "//src:warning_lib",
)

report_test(
    name = "clippy_machine_output_test",
    expected_tool = "clippy",
    expected_uri = "src/warning_lib.rs",
    report = "machine_clippy_report",
)
