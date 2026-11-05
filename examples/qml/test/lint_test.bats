bats_load_library "bats-support"
bats_load_library "bats-assert"

function assert_qml_lints() {
	echo <<"EOF" | assert_output --partial
Main.qml:2:1:
Unused import [unused-imports]
EOF
}

@test "should produce reports" {
	run aspect lint --strategy=soft --tips:silence=add-aspect-api-token-github-actions -- //src/...
	assert_success
	assert_qml_lints
}
