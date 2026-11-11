bats_load_library "bats-support"
bats_load_library "bats-assert"

setup() {
    fixture_dir="$(mktemp -d .format-test.XXXXXX)"
    cd "$fixture_dir"
    printf '%s\n' '{hello="world";}' > first.nix
    printf '%s\n' '{answer=42;}' > 'second file.nix'
    cp first.nix first.original
    cp 'second file.nix' second.original
}

teardown() {
    cd ..
    rm -rf "$fixture_dir"
}

@test "nixfmt checks without modifying files, fixes multiple files, then passes check" {
    run bazel run //tools/format:format.check -- first.nix 'second file.nix'
    assert_failure
    cmp first.nix first.original
    cmp 'second file.nix' second.original

    run bazel run //tools/format -- first.nix 'second file.nix'
    assert_success
    [ "$(cat first.nix)" = '{ hello = "world"; }' ]
    [ "$(cat 'second file.nix')" = '{ answer = 42; }' ]

    run bazel run //tools/format:format.check -- first.nix 'second file.nix'
    assert_success
}
