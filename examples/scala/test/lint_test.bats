bats_load_library "bats-support"
bats_load_library "bats-assert"

@test "should produce lint reports with scalafix" {
	run aspect lint --strategy=soft --tips:silence=add-aspect-api-token-github-actions -- //src/...

	assert_success

	# DisableSyntax.var prints diagnostic
	assert_output --partial "src/App.scala:5 · Scalafix — [DisableSyntax.var] mutable state should be avoided"
	
	# ProcedureSyntax produces rewrite
	assert_output --partial "src/App.scala:1 · Scalafix — Scalafix rewrite suggested"

	# RemoveUnused produces rewrite
	assert_output --partial "src/Foo.scala:1 · Scalafix — Scalafix rewrite suggested"
}
