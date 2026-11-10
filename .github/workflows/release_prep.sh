#!/usr/bin/env bash
# Prepares a release archive for the module selected by the tag's prefix.
# Called by release_ruleset.yaml as: release_prep.sh <tag>
# Writes release notes to stdout.
set -o errexit -o nounset -o pipefail

# Argument provided by reusable workflow caller, see
# https://github.com/bazel-contrib/.github/blob/d197a6427c5435ac22e56e33340dff912bc9334e/.github/workflows/release_ruleset.yaml#L72
TAG=$1

# ---- Changelog ------------------------------------------------------------
# GitHub's auto-generated notes are disabled in the release workflows
# (generate_release_notes: false) because they (a) diff against the previous
# tag of ANY prefix (a v* release would diff against a rust-v* tag and vice
# versa) and (b) list every PR in the repo regardless of which module it
# touched. We generate the changelog ourselves instead so it contains exactly
# the changes to THIS module since the previous release on the SAME version
# line.
#
#   emit_changelog <tag-prefix> [pathspec...]
#
# <tag-prefix> selects the version line (e.g. "v", "rust-v"); the previous
# release is the next-lower tag sharing that prefix. The optional pathspecs
# restrict the log to the module's subtree (omit to include the whole repo).
emit_changelog() {
	local prefix="$1"
	shift
	local paths=("$@")

	# Release runners often check out shallow / without tags; deepen so the
	# tag list and the prev..TAG range are complete. Best-effort, offline-safe.
	git fetch --tags --quiet 2>/dev/null || true
	git fetch --tags --unshallow --quiet 2>/dev/null || true

	# Previous release on the same version line: version-sort the tags sharing
	# this prefix, find TAG, and take the entry just below it. NB: "v*" does
	# not match "rust-v*" tags, so the prefixes don't bleed into each other.
	local prev
	prev=$(git tag --list "${prefix}*" --sort=-version:refname |
		grep -x -F -A1 -- "$TAG" | tail -n1)

	local range
	if [[ -z "$prev" || "$prev" == "$TAG" ]]; then
		range="$TAG" # First release on this line: full history up to the tag.
		prev=""
	else
		range="${prev}..${TAG}"
	fi

	local log
	log=$(git log --no-merges --format='- %s' "$range" -- "${paths[@]}")

	echo "## What's Changed"
	echo
	if [[ -n "$log" ]]; then
		echo "$log"
	else
		echo "_No changes to this module since ${prev:-the initial commit}._"
	fi
	echo

	if [[ -n "$prev" ]]; then
		echo "**Full Changelog**: https://github.com/bazel-contrib/rules_lint/compare/${prev}...${TAG}"
		echo
	fi
}

# ---- Sub-module releases (rules_lint_rust, ...) --------------------
# These archives are just the module's subtree hoisted to the archive root,
# with the module version patched in. Add a module by adding a
# "<tag-prefix>*) <module root>" case below (plus a trigger workflow and its
# .bcr/<module root>/ templates).
SRC_MODULE_ROOT=""
case "$TAG" in
rust-v*)
	SRC_MODULE_ROOT="lint/rust"
	;;
scala-v*)
	SRC_MODULE_ROOT="lint/scala"
	;;
v*) ;; # Root module release, handled below.
*)
	echo "Unknown tag format: ${TAG}" >&2
	exit 1
	;;
esac
if [[ -n "$SRC_MODULE_ROOT" ]]; then
	# Tag carries the module's prefix (e.g. rust-v1.2.3), so the archive is
	# rules_lint-rust-v1.2.3.tar.gz, matching strip_prefix "rules_lint-{TAG}"
	# in the module's .bcr source.template.json.
	MODULE_VERSION="${TAG#*-v}"
	PREFIX="rules_lint-${TAG}"
	ARCHIVE="rules_lint-${TAG}.tar.gz"

	# Archive the subtree as a tree-ish ("TAG:lint/rust") rather than a
	# pathspec: it hoists MODULE.bazel to the archive root, and it sidesteps
	# the root .gitattributes export-ignore rules that exclude the nested
	# modules from the root module's archive.
	UNPACK_DIR=$(mktemp -d)
	git archive --format=tar --prefix="${PREFIX}/" "${TAG}:${SRC_MODULE_ROOT}" |
		tar -xf - -C "$UNPACK_DIR"

	# Patch MODULE.bazel: stamp the release version (0.0.0 -> real) and drop
	# the dev-only local_path_override block (consumers resolve
	# rules_lint from the registry).
	git show "${TAG}:${SRC_MODULE_ROOT}/MODULE.bazel" |
		sed -e "s/^    version = \"0\.0\.0\"/    version = \"${MODULE_VERSION}\"/" \
			-e '/^local_path_override($/,/^)$/d' |
		cat -s >"${UNPACK_DIR}/${PREFIX}/MODULE.bazel"

	MODULE_NAME=$(sed -n 's/^    name = "\([^"]*\)",$/\1/p' "${UNPACK_DIR}/${PREFIX}/MODULE.bazel" | head -1)

	tar -cf - -C "$UNPACK_DIR" "${PREFIX}" | gzip >"$ARCHIVE"
	rm -rf "$UNPACK_DIR"

	cat <<EOF
Add to your \`MODULE.bazel\` file:

\`\`\`starlark
bazel_dep(name = "${MODULE_NAME}", version = "${MODULE_VERSION}")
\`\`\`

Then follow the setup instructions in
https://github.com/bazel-contrib/rules_lint/blob/${TAG}/${SRC_MODULE_ROOT}/README.md
EOF

	# Changes under this module's subtree since the previous <prefix> tag.
	echo
	emit_changelog "${TAG%%-v*}-v" "$SRC_MODULE_ROOT"
	exit 0
fi

# ---- Root module release (rules_lint) -------------------------------
# The prefix is chosen to match what GitHub generates for source archives
PREFIX="rules_lint-${TAG:1}"
ARCHIVE="rules_lint-$TAG.tar.gz"
ARCHIVE_TMP=$(mktemp)

# NB: configuration for 'git archive' is in /.gitattributes
git archive --format=tar --prefix=${PREFIX}/ ${TAG} >$ARCHIVE_TMP

# Add generated API docs to the release, see https://github.com/bazelbuild/bazel-central-registry/issues/5593
docs="$(mktemp -d)"; targets="$(mktemp)"
bazel --output_base="$docs" query --output=label --output_file="$targets" 'kind("starlark_doc_extract rule", //lint/... union //format/...)'
bazel --output_base="$docs" build --target_pattern_file="$targets"
tar --create --auto-compress \
    --directory "$(bazel --output_base="$docs" info bazel-bin)" \
    --file "$GITHUB_WORKSPACE/${ARCHIVE%.tar.gz}.docs.tar.gz" .

############
# Patch up the archive to have integrity hashes for built binaries that we downloaded in the GHA workflow.
# Now that we've run `git archive` we are free to pollute the working directory.

# Delete the placeholder file
tar --file $ARCHIVE_TMP --delete ${PREFIX}/tools/integrity.bzl

# A single uploaded artifact is extracted flat into the workspace root, not into
# go-binaries/ (actions/download-artifact#455). Move the files into go-binaries/
# so the integrity glob below and `release_files: go-binaries/*` find them; if
# they are left in the root the glob matches nothing and the integrity dict is
# published empty.
if compgen -G '*.sha256' >/dev/null; then
  mkdir -p go-binaries
  for f in *.sha256; do
    mv "$f" "${f%.sha256}" go-binaries/
  done
fi

mkdir -p ${PREFIX}/tools
cat >${PREFIX}/tools/integrity.bzl <<EOF
"Generated during release by release_prep.sh"

RELEASED_BINARY_INTEGRITY = $(
  jq \
    --from-file .github/workflows/integrity.jq \
    --slurp \
    --raw-input go-binaries/*.sha256
)
EOF

# Fail the release if any sarif_parser platform the toolchain requires is missing
# an integrity entry. A dropped or unbuilt release binary otherwise yields an
# incomplete RELEASED_BINARY_INTEGRITY that publishes without error; the gap only
# surfaces later in a consuming repo at `bazel build` time as
# "key \"sarif_parser-<platform>\" not found in dictionary".
# The required platforms are the keys of SARIF_PARSER_PLATFORMS.
missing=()
for platform in $(grep -oE '^    "[a-z0-9_]+": struct\(' tools/toolchains/sarif_parser_toolchain.bzl | sed -E 's/^    "([^"]+)".*/\1/'); do
  ext=""
  [[ "$platform" == windows_* ]] && ext=".exe"
  key="sarif_parser-${platform}${ext}"
  if ! grep -q "\"${key}\"" ${PREFIX}/tools/integrity.bzl; then
    missing+=("$key")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: release integrity is missing entries for: ${missing[*]}" >&2
  echo "The go-binaries/ artifact did not contain a .sha256 for every required" >&2
  echo "sarif_parser platform. Aborting to avoid publishing a broken release." >&2
  echo "Generated tools/integrity.bzl was:" >&2
  cat ${PREFIX}/tools/integrity.bzl >&2
  exit 1
fi

# Append that generated file back into the archive
tar --file $ARCHIVE_TMP --append ${PREFIX}/tools/integrity.bzl

# END patch up the archive
############

gzip <$ARCHIVE_TMP >$ARCHIVE
# Note: this happens to match what we publish to BCR in source.json, though it's not required to
INTEGRITY="sha256-$(shasum -a 256 $ARCHIVE | xxd -p -r | base64)"

cat << EOF
Add this to your `MODULE.bazel` file:

\`\`\`starlark
bazel_dep(name = "rules_lint", version = "${TAG:1}")
\`\`\`

This repo also provides a \`lint\` task for the [Aspect CLI].
Add this to your \`MODULE.aspect\` file:

\`\`\`starlark
# AXL dependencies; see https://github.com/aspect-extensions
axl_archive_dep(
    name = "rules_lint",
    urls = ["https://github.com/bazel-contrib/rules_lint/releases/download/${TAG}/rules_lint-${TAG}.tar.gz"],
    integrity = "${INTEGRITY}",
    strip_prefix = "rules_lint-${TAG:1}",
    dev = True,
    auto_use_tasks = True,
)
\`\`\`

Then, follow the install instructions for
- linting: https://github.com/bazel-contrib/rules_lint/blob/${TAG}/docs/linting.md
- formatting: https://github.com/bazel-contrib/rules_lint/blob/${TAG}/docs/formatting.md

[Aspect CLI]: https://docs.aspect.build/cli
EOF

# Changes since the previous v* tag. No pathspec: the root module is built
# from the whole repo (minus the export-ignored nested modules).
echo
emit_changelog "v"
