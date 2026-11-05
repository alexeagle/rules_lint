# buildifier: disable=bzl-visibility
load("@rules_lint//lint/private:machine_report_testing.bzl", "report_test")  # @unused: used in commented-out tests
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_java//java:defs.bzl", "java_library")
load(
    "//tools/lint:linters.bzl",
    "checkstyle_test",
    "pmd_test",
)
load(
    ":machine_output.bzl",
    "machine_checkstyle_report",
    "machine_pmd_report",
    "machine_spotbugs_report",
)

write_file(
    name = "java_code_generator",
    out = "generated.java",
    content = ["public class generated { protected void finalize(int a) {} }"],
)

java_library(
    name = "generated_java",
    srcs = ["generated.java"],
)

pmd_test(
    name = "pmd_should_ignore_generated",
    srcs = [":generated_java"],
)

pmd_test(
    name = "pmd",
    srcs = ["//src:foo"],
    # We don't have any PMD errors in this file
    expected_exit_code = 0,
)

checkstyle_test(
    name = "checkstyle",
    srcs = ["//src:bar"],
    expected_exit_code = 5,
)

machine_pmd_report(
    name = "machine_pmd_report",
    src = "//src:foo",
)

# report_test(
#     name = "pmd_machine_output_test",
#     expected_tool = "PMD",
#     expected_uri = "src/Foo.java",
#     report = "machine_pmd_report",
# )
# FIXME: report isn't finding any files??
# # assert_physical_artifact_location_uri "src/Hello.java"

machine_spotbugs_report(
    name = "machine_spotbugs_report",
    src = "//src:foo",
)

# TODO: spotbugs is not working yet.
# It doesn't seem to print source locations (perhaps because it only works from bytecode)
# It's the same problem I solved by starting Error Prone!!
# report_test(
#     name = "spotbugs_machine_output_test",
#     expected_tool = "SpotBugs",
#     expected_uri = "src/Foo.java",
#     report = "machine_spotbugs_report",
# )

machine_checkstyle_report(
    name = "machine_checkstyle_report",
    src = "//src:bar",
)

# report_test(
#     name = "checkstyle_machine_output_test",
#     expected_tool = "Checkstyle",
#     expected_uri = "src/Bar.java",
#     report = "machine_checkstyle_report",
# )
