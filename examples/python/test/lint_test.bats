bats_load_library "bats-support"
bats_load_library "bats-assert"

function assert_python_lints() {
	# Ruff
	echo <<"EOF" | assert_output --partial
src/unused_import.py:18:8: F401 [*] `os` imported but unused
Found 2 errors.
[*] 1 fixable with the `--fix` option.
EOF

	# pylint
	echo <<"EOF" | assert_output --partial
src/unused_import.py:15:0: C0301: Line too long (180/120) (line-too-long)
src/unused_import.py:22:6: W1302: Invalid format string (bad-format-string)
src/unused_import.py:18:0: W0611: Unused import os (unused-import)
EOF

	# pydoclint
	assert_output --partial "src/missing_doc_arg.py:4: DOC101: Function \\`documented_add\\`: Docstring contains fewer arguments than in function signature."

	# Ty
	echo <<"EOF" | assert_output --partial
error[unsupported-operator]: Operator `+` is unsupported between objects of type `Literal[10]` and `Literal["test"]`
 --> src/unsupported_operator.py:3:5
  |
1 | # Demo with just running ty from the examples dir:
2 | # $ ./lint.sh src:unsupported_operator
3 | a = 10 + "test"
  |     ^^^^^^^^^^^
  |
info: rule `unsupported-operator` is enabled by default

Found 1 diagnostic
EOF

	# Flake8
	assert_output --partial "src/unused_import.py:18:1: F401 'os' imported but unused"
}

@test "should produce reports" {
	run aspect lint --strategy=soft --tips:silence=add-aspect-api-token-github-actions -- //src/...
	assert_success
	assert_python_lints
}
