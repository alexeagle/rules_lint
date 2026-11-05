bats_load_library "bats-support"
bats_load_library "bats-assert"

function assert_java_lints() {
	# PMD
	echo <<"EOF" | assert_output --partial
* file: src/Foo.java
    src:  Foo.java:9:9
    rule: FinalizeOverloaded
    msg:  Finalize methods should not be overloaded
    code: protected void finalize(int a) {}
EOF
}

@test "should produce reports" {
	run aspect lint --strategy=soft --tips:silence=add-aspect-api-token-github-actions -- //src/...
	assert_success
	assert_java_lints
}

