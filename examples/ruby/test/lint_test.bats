bats_load_library "bats-support"
bats_load_library "bats-assert"

function assert_ruby_lints() {
	# RuboCop
	echo <<"EOF" | assert_output --partial
C:  1:  1: [Correctable] Style/FrozenStringLiteralComment: Missing frozen string literal comment.
W:  4:  1: [Correctable] Lint/UselessAssignment: Useless assignment to variable - unused_variable.
C:  6:101: Layout/LineLength: Line is too long. [115/100]
EOF

	# Standard Ruby
	echo <<"EOF" | assert_output --partial
== src/hello.rb ==
W:  4:  1: [Correctable] Lint/UselessAssignment: Useless assignment to variable - unused_variable.
C: 19:  3: [Correctable] Layout/IndentationWidth: Use 2 (not 4) spaces for indentation.
W: 29:  1: [Correctable] Lint/UselessAssignment: Useless assignment to variable - message.
W: 32:  1: [Correctable] Lint/UselessAssignment: Useless assignment to variable - numbers.
EOF
}

@test "should produce reports" {
	run aspect lint --strategy=soft --tips:silence=add-aspect-api-token-github-actions -- //src/...
	assert_success
	assert_ruby_lints
}
