load("@jq.bzl//jq:jq.bzl", "jq_test")
load("//tools/lint:linters.bzl", "golangci_lint_facts_test", "golangci_lint_test")
load(":machine_output.bzl", "machine_golangci_lint_facts_report")

# golangci-lint flags the non-constant format string in hello.go (govet printf),
# so the linter exits 1.
golangci_lint_test(
    name = "golangci_lint_finds_issue",
    srcs = ["//src:hello"],
    expected_exit_code = 1,
)

# The greeting library is clean, so the linter exits 0 (no false positives).
golangci_lint_test(
    name = "golangci_lint_clean",
    srcs = ["//src:greeting"],
    expected_exit_code = 0,
)

# Every lint action starts with an empty private cache. Exit 1 alone cannot
# distinguish the expected printf finding from a false undefined-symbol error.
golangci_lint_facts_test(
    name = "golangci_lint_cross_package_facts",
    srcs = ["//test/analyzerfacts/consumer"],
    expected_exit_code = 1,
)

golangci_lint_facts_test(
    name = "golangci_lint_cross_package_facts_clean",
    srcs = ["//test/analyzerfacts/clean"],
    expected_exit_code = 0,
)

machine_golangci_lint_facts_report(
    name = "analyzer_facts_report",
    src = "//test/analyzerfacts/consumer",
)

# Expected message and location verified against native golangci-lint 2.12.2.
# Exact results also reject false typecheck errors and dependency diagnostics.
jq_test(
    name = "golangci_lint_cross_package_diagnostic",
    file1 = ":analyzer_facts_report",
    file2 = "analyzer_facts.expected.json",
    filter1 = """[.runs[].results[] | {
        rule: .ruleId,
        message: .message.text,
        uri: .locations[0].physicalLocation.artifactLocation.uri,
        line: .locations[0].physicalLocation.region.startLine,
        column: .locations[0].physicalLocation.region.startColumn
    }]""",
    filter2 = ".",
)
