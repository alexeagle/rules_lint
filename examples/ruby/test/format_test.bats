setup() {
    fixture_dir="$(mktemp -d .format-test.XXXXXX)"
    cd "$fixture_dir"
    cat > .streerc <<'CONFIG'
--print-width=30
--plugins=plugin/trailing_comma
--ignore-files=ignored.rb
CONFIG
    echo 'numbers=[111_111,222_222,333_333]' > source.rb
    echo 'ignored=[1,2,3]' > ignored.rb
    ln -s ignored.rb alias.rb
}

teardown() {
    cd ..
    rm -rf "$fixture_dir"
}

@test "stree checks and fixes using local configuration without changing ignored or symlink inputs" {
    run bazel run //tools/format:format.check
    [ "$status" -ne 0 ]
    [ "$(cat source.rb)" = 'numbers=[111_111,222_222,333_333]' ]

    run bazel run //tools/format
    [ "$status" -eq 0 ]
    run cat source.rb
    [ "$output" = 'numbers = [
  111_111,
  222_222,
  333_333,
]' ]
    [ "$(cat ignored.rb)" = 'ignored=[1,2,3]' ]
    [ -L alias.rb ]

    run bazel run //tools/format:format.check
    [ "$status" -eq 0 ]
}
