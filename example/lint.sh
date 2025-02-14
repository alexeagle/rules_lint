#!/usr/bin/env bash
#
# Shows an end-to-end workflow for linting without failing the build.
# This is meant to mimic the behavior of the `bazel lint` command that you'd have
# by using the Aspect CLI [lint command](https://docs.aspect.build/cli/commands/aspect_lint).
#
# To make the build fail when a linter warning is present, run with `--fail-on-violation`.
# To auto-fix violations, run with `--fix` (or `--fix --dry-run` to just print the patches)
#
# NB: this is an example of code you could paste into your repo, meaning it's userland
# and not a supported public API of rules_lint. It may be broken and we don't make any
# promises to fix issues with using it.
# We recommend using Aspect CLI instead!
set -o errexit -o pipefail -o nounset

if [ "$#" -eq 0 ]; then
	echo "usage: lint.sh [target pattern...]"
	exit 1
fi

fix=""
buildevents=$(mktemp)
filter='.namedSetOfFiles | values | .files[] | select(.name | endswith($ext)) | ((.pathPrefix | join("/")) + "/" + .name)'

unameOut="$(uname -s)"
case "${unameOut}" in
Linux*) machine=Linux ;;
Darwin*) machine=Mac ;;
CYGWIN*) machine=Windows ;;
MINGW*) machine=Windows ;;
MSYS_NT*) machine=Windows ;;
*) machine="UNKNOWN:${unameOut}" ;;
esac

args=()
if [ $machine == "Windows" ]; then
	# avoid missing linters on windows platform
	args=("--aspects=$(echo //tools/lint:linters.bzl%{flake8,pmd,ruff,vale,clang_tidy} | tr ' ' ',')")
else
	args=("--aspects=$(echo //tools/lint:linters.bzl%{buf,eslint,flake8,keep_sorted,ktlint,pmd,ruff,shellcheck,stylelint,vale,clang_tidy,spotbugs} | tr ' ' ',')")
fi

# NB: perhaps --remote_download_toplevel is needed as well with remote execution?
args+=(
	# Allow lints of code that fails some validation action
	# See https://github.com/aspect-build/rules_ts/pull/574#issuecomment-2073632879
	"--norun_validations"
	"--build_event_json_file=$buildevents"
	# Required for the buf allow_comment_ignores option to work properly
	# See https://github.com/bufbuild/rules_buf/issues/64#issuecomment-2125324929
	"--experimental_proto_descriptor_sets_include_source_info"
	"--output_groups=rules_lint_human"
	"--remote_download_regex='.*AspectRulesLint.*'"
)

# This is a rudimentary flag parser.
if [ $1 == "--fail-on-violation" ]; then
	args+=(
		"--@aspect_rules_lint//lint:fail_on_violation"
		"--keep_going"
	)
	shift
fi

# Allow a `--fix` option on the command-line.
# This happens to make output of the linter such as ruff's
# [*] 1 fixable with the `--fix` option.
# so that the naive thing of pasting that flag to lint.sh will do what the user expects.
if [ $1 == "--fix" ]; then
	fix="patch"
	args+=(
		"--@aspect_rules_lint//lint:fix"
		"--output_groups=rules_lint_patch"
	)
	shift
fi
# NB: the --dry-run flag must immediately follow the --fix flag
if [ $1 == "--dry-run" ]; then
	fix="print"
	shift
fi

# Run linters
bazel build ${args[@]} $@

# TODO: Maybe this could be hermetic with bazel run @aspect_bazel_lib//tools:jq or sth
# jq on windows outputs CRLF which breaks this script. https://github.com/jqlang/jq/issues/92
valid_reports=$(jq --arg ext .out --raw-output "$filter" "$buildevents" | tr -d '\r')

# Show the results.
while IFS= read -r report; do
	# Exclude coverage reports, and check if the output is empty.
	if [[ "$report" == *coverage.dat ]] || [[ ! -s "$report" ]]; then
		# Report is empty. No linting errors.
		continue
	fi
	echo "From ${report}:"
	cat "${report}"
	echo
done <<<"$valid_reports"

if [ -n "$fix" ]; then
	valid_patches=$(jq --arg ext .patch --raw-output "$filter" "$buildevents" | tr -d '\r')
	while IFS= read -r patch; do
		# Exclude coverage, and check if the patch is empty.
		if [[ "$patch" == *coverage.dat ]] || [[ ! -s "$patch" ]]; then
			# Patch is empty. No linting errors.
			continue
		fi

		case "$fix" in
		"print")
			echo "From ${patch}:"
			cat "${patch}"
			echo
			;;
		"patch")
			patch -p1 <${patch}
			;;
		*)
			echo >2 "ERROR: unknown fix type $fix"
			exit 1
			;;
		esac

	done <<<"$valid_patches"
fi
