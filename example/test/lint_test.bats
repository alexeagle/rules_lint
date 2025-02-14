bats_load_library "bats-support"
bats_load_library "bats-assert"

function assert_lints() {
	# Shellcheck
	echo <<"EOF" | assert_output --partial
In src/hello.sh line 3:
[ -z $THING ] && echo "hello world"
     ^----^ SC2086 (info): Double quote to prevent globbing and word splitting.
EOF

	# Ruff
	echo <<"EOF" | assert_output --partial
src/unused_import.py:13:8: F401 [*] `os` imported but unused
Found 1 error.
[*] 1 fixable with the `--fix` option.
EOF

	# Flake8
	assert_output --partial "src/unused_import.py:13:1: F401 'os' imported but unused"

	# PMD
	echo <<"EOF" | assert_output --partial
* file: src/Foo.java
    src:  Foo.java:9:9
    rule: FinalizeOverloaded
    msg:  Finalize methods should not be overloaded
    code: protected void finalize(int a) {}
EOF

	# ktlint
	assert_output --partial "src/hello.kt:1:1: File name 'hello.kt' should conform PascalCase (standard:filename)"

	# ESLint
	echo <<"EOF" | assert_output --partial
src/file.ts
  2:7  error  Type string trivially inferred from a string literal, remove type annotation  @typescript-eslint/no-inferrable-types
EOF
	# If type declarations are missing, the following errors will be reported
	refute_output --partial '@typescript-eslint/no-unsafe-call'
	refute_output --partial '@typescript-eslint/no-unsafe-member-access'

	# Buf
	assert_output --partial 'src/file.proto:3:1:Import "src/unused.proto" is unused.'

	# Vale
	echo <<"EOF" | assert_output --partial
3:47  warning  Try to avoid using              Google.We
               first-person plural like 'We'.
EOF

	# stylelint
	echo <<"EOF" | assert_output --partial
src/hello.css
  11:5  ✖  Unexpected empty block  block-no-empty
EOF
}

@test "should produce reports" {
	run $BATS_TEST_DIRNAME/../lint.sh //src:all --no@aspect_rules_lint//lint:color
	assert_success
	assert_lints

	run $BATS_TEST_DIRNAME/../lint.sh --fix --dry-run //src:all
	assert_success

	# Check that we created a 'patch -p1' format file that fixes the ESLint violation
	run cat bazel-bin/src/ts.AspectRulesLintESLint.patch
	assert_success
	echo <<"EOF" | assert_output --partial
--- a/src/file.ts
+++ b/src/file.ts
@@ -1,3 +1,3 @@
 // this is a linting violation
-const a: string = "a";
+const a = "a";
 console.log(a);
EOF

	# Check that we created a 'patch -p1' format file that fixes the ruff violation
	run cat bazel-bin/src/unused_import.AspectRulesLintRuff.patch
	assert_success
	echo <<"EOF" | assert_output --partial
--- a/src/unused_import.py
+++ b/src/unused_import.py
@@ -10,4 +10,3 @@
 # src/unused_import.py:12:8: F401 [*] `os` imported but unused
 # Found 1 error.
 # [*] 1 potentially fixable with the --fix option.
-import os
EOF
}

@test "should fail when --fail-on-violation is passed" {
	run $BATS_TEST_DIRNAME/../lint.sh --fail-on-violation //src:all
	assert_failure
	assert_lints
}

@test "should use nearest ancestor .eslintrc file" {
	run $BATS_TEST_DIRNAME/../lint.sh //src/subdir:eslint-override
	assert_success
	# This lint check is disabled in the .eslintrc.cjs file
	refute_output --partial "Unexpected 'debugger' statement"
}
