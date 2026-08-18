bats_load_library "bats-support"
bats_load_library "bats-assert"

@test "Oxlint reports original violations while offering a patch" {
    run bazel build \
        --config=lint \
        --output_groups=rules_lint_human,rules_lint_patch \
        --@rules_lint//lint:fix \
        //src:oxlint_fixable
    assert_success

    run cat bazel-bin/src/oxlint_fixable.AspectRulesLintOxlint.out.exit_code
    assert_output "1"

    run cat bazel-bin/src/oxlint_fixable.AspectRulesLintOxlint.out
    assert_output --partial "Unexpected const enum"

    run cat bazel-bin/src/oxlint_fixable.AspectRulesLintOxlint.patch
    assert_output --partial -- "-const enum Direction"
    assert_output --partial -- "+enum Direction"
}
