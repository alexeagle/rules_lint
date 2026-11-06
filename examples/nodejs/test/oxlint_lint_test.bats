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
    assert_output --partial -- "+const stageDone = 1;"
    refute_output --partial -- "+const stageTwo = 1;"
}

@test "Oxlint type-aware rules resolve the target tsconfig and dependency types" {
    run bazel build \
        --aspects=//tools/lint:linters.bzl%oxlint_typed \
        --output_groups=rules_lint_human,rules_lint_machine \
        //src/oxlint_typed:typed
    assert_success

    run cat bazel-bin/src/oxlint_typed/typed.AspectRulesLintOxlint.out
    assert_output --partial "no-floating-promises"
    run cat bazel-bin/src/oxlint_typed/typed.AspectRulesLintOxlint.out.exit_code
    assert_output "1"
    run cat bazel-bin/src/oxlint_typed/typed.AspectRulesLintOxlint.report
    assert_output --partial "no-floating-promises"
}
