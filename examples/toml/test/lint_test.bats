bats_load_library "bats-support"
bats_load_library "bats-assert"

function assert_toml_lints() {
	echo <<"EOF" | assert_output --partial
conflicting keys
EOF

	echo <<"EOF" | assert_output --partial
src/bad.toml
EOF

	refute_output --partial "/execroot/"
	refute_output --partial "/sandbox/"
}

@test "should produce reports" {
	run aspect lint --strategy=soft --tips:silence=add-aspect-api-token-github-actions -- //src/...
	assert_success
	assert_toml_lints
}
