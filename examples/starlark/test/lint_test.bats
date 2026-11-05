bats_load_library "bats-support"
bats_load_library "bats-assert"

function assert_starlark_lints() {
	echo <<"EOF" | assert_output --partial
"uri": "src/defs.bzl"
EOF

	echo <<"EOF" | assert_output --partial
"uri": "src/custom.star"
EOF

	echo <<"EOF" | assert_output --partial
list-append: Prefer using \".append()\" to adding a single element list.
EOF
}

@test "should produce reports" {
	run aspect lint --strategy=soft --tips:silence=add-aspect-api-token-github-actions -- //src/...
	assert_success
	assert_starlark_lints
}
