#!/usr/bin/env bash

set -o nounset -o errexit -o pipefail

BUILD_WORKSPACE_DIRECTORY=$TEST_TMPDIR source "$TEST_SRCDIR/_main/format/private/format.sh"

git init --initial-branch=test

touch src.{js,css} gen{1,2,3}.js {src,more}.go

cat >.gitignore <<EOF
ignore*
EOF

git config user.email "author@example.com"
git config user.name "A U Thor"
git add .
git commit --all --message 'initial commit'

# .gitignore files should be excluded
touch ignore.scala
scala=$(ls-files Scala)
[[ "$scala" == "" ]] || {
    echo >&2 -e "expected ls-files to be empty, was\n$scala"
    exit 1
}

# Untracked files should be formatted
touch untracked.kt
kt=$(ls-files Kotlin)
[[ "$kt" == "untracked.kt" ]] || {
    echo >&2 -e "expected ls-files to return untracked.kt, was\n$kt"
    exit 1
}

# .gitattributes should allow more excludes
cat >.gitattributes <<EOF
gen1.js rules-lint-ignored
gen2.js rules-lint-ignored=false
gen2.js gitlab-generated=true
gen3.js linguist-generated
EOF
js=$(ls-files JavaScript)
[[ "$js" == "src.js" ]] || {
    echo >&2 -e "expected ls-files to return src.js, was\n$js"
    exit 1
}
js=$(ls-files JavaScript src.js gen1.js gen2.js gen3.js)
[[ "$js" == "src.js" ]] || {
    echo >&2 -e "expected ls-files to return src.js, was\n$js"
    exit 1
}
js=$(ls-files JavaScript  gen1.js gen2.js gen3.js src.js)
[[ "$js" == "src.js" ]] || {
    echo >&2 -e "expected ls-files to return src.js, was\n$js"
    exit 1
}
js=$(disable_git_attribute_checks=true ls-files JavaScript src.js gen1.js gen2.js gen3.js)
expected='src.js
gen1.js
gen2.js
gen3.js'
[[ "$js" == "$expected" ]] || {
    echo >&2 -e "expected ls-files to return src.js gen1.js gen2.js gen3.js, was\n$js"
    exit 1
}

# deleted files should be ignored
git rm src.css
css=$(ls-files CSS)
[[ "$css" == "" ]] || {
    echo >&2 -e "expected ls-files to be empty, was\n$css"
    exit 1
}

# should not fail when folder name contains spaces
mkdir -p "complex-structure/folder with space"
touch "complex-structure/folder with space/src.go"
go=$(ls-files Go)
expected='complex-structure/folder with space/src.go
more.go
src.go'
[[ "$go" == "$expected" ]] || {
    echo >&2 -e "expected ls-files to return complex-structure/folder with space/src.go more.go src.go, was\n$go"
    exit 1
}

# patterns should match filenames
go=$(ls-files Go src.go)
[[ "$go" == "src.go" ]] || {
    echo >&2 -e "expected ls-files to return src.go, was\n$go"
    exit 1
}

# when a path argument contains spaces (e.g. a Go template directory like
# 'foo/{{ .X }}/bar.tf'), the path must reach `find` as a single argument
# instead of being word-split into 'foo/{{', '.X', '}}/bar.tf'.
mkdir -p 'templated/{{ .X }}'
touch 'templated/{{ .X }}/file.tf'
git add .
git commit --all --message 'add templated tf path'
tf=$(ls-files Terraform 'templated/{{ .X }}/file.tf' 2>/tmp/ls-files-stderr)
[[ "$tf" == 'templated/{{ .X }}/file.tf' ]] || {
    echo >&2 -e "expected ls-files to return the templated tf path, was\n$tf"
    exit 1
}
[[ ! -s /tmp/ls-files-stderr ]] || {
    echo >&2 -e "expected no stderr from ls-files, was\n$(cat /tmp/ls-files-stderr)"
    exit 1
}

# Ruby selects .rb and .rake files, including nested files.
# Extensionless Ruby filenames and other Ruby dialects remain excluded.
mkdir -p ruby/nested
touch ruby/nested/source.rb ruby/task.rake ruby/Rakefile ruby/Gemfile ruby/types.rbs
expected='ruby/nested/source.rb
ruby/task.rake'
for ruby in "$(ls-files Ruby | sort)" "$(ls-files Ruby ruby | sort)"; do
    [[ "$ruby" == "$expected" ]] || {
        echo >&2 -e "expected Ruby files to be\n$expected, was\n$ruby"
        exit 1
    }
done

# sparse-checkout should be supported
mkdir tree1 tree2
touch tree1/src.js tree2/src.js
git add .
git commit --all --message 'prepare sparse-checkout'
git sparse-checkout init

js=$(ls-files JavaScript)
[[ "$js" == "src.js" ]] || {
    echo >&2 -e "expected ls-files to return src.js, was\n$js"
    exit 1
}

git sparse-checkout add tree1
js=$(ls-files JavaScript)
expected='src.js
tree1/src.js'

[[ "$js" == "$expected" ]] || {
    echo >&2 -e "expected ls-files to return $expected, was\n$js"
    exit 1
}

git sparse-checkout add tree2
js=$(ls-files JavaScript)
expected='src.js
tree1/src.js
tree2/src.js'

[[ "$js" == "$expected" ]] || {
    echo >&2 -e "expected ls-files to return $expected, was\n$js"
    exit 1
}

git sparse-checkout disable

# BUILD_WORKING_DIRECTORY scopes ls-files to a subdirectory
mkdir -p sub
touch sub/sub.js
git add sub/sub.js
git commit --message 'add subdirectory js file'
(
  BUILD_WORKSPACE_DIRECTORY="$(pwd)" BUILD_WORKING_DIRECTORY="$(pwd)/sub" \
    source "$TEST_SRCDIR/_main/format/private/format.sh"
  sub_js=$(ls-files JavaScript)
  [[ "$sub_js" == "sub.js" ]] || {
    echo >&2 -e "expected ls-files to return sub.js when scoped to sub/, was\n$sub_js"
    exit 1
  }
)
