bats_load_library "bats-support"
bats_load_library "bats-assert"

function assert_cpp_lints() {
	# clang-tidy
	assert_output --partial "clang-tidy"
	# cppcheck
	assert_output --partial "cppcheck"
}

@test "should produce reports" {
	run aspect lint $REMOTE_FLAG --strategy=soft --tips:silence=add-aspect-api-token-github-actions -- //src/...
	assert_success
	assert_cpp_lints
}

# Regression for https://github.com/aspect-build/rules_lint/issues/899: clang-tidy's
# summary lines (warnings generated / Suppressed / Use -header-filter / treated as
# error) must be stripped while real diagnostics are kept, else a clean run trips
# --@rules_lint//lint:fail_on_violation.
@test "clang-tidy report excludes summary statistics" {
	bazel build --aspects=//tools/lint:linters.bzl%clang_tidy --output_groups=rules_lint_human //src:hello_cc
	report=$(find -L "$(bazel info bazel-bin)/src" -name '*hello*ClangTidy*.out' | head -n 1)
	run cat "$report"
	assert_success
	assert_output --partial "warning:"
	refute_output --partial "warnings generated"
	refute_output --partial "Suppressed"
	refute_output --partial "Use -header-filter"
}

@test "clang-tidy report strips the 'treated as error' summary" {
	bazel build --aspects=//tools/lint:linters.bzl%clang_tidy --output_groups=rules_lint_human //test:inconsistent_cc
	report=$(find -L "$(bazel info bazel-bin)/test" -name '*inconsistent*ClangTidy*.out' | head -n 1)
	run cat "$report"
	assert_success
	assert_output --partial "error:"
	refute_output --partial "treated as error"
}
