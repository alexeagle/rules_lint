#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
RELEASES=$(mktemp)
RAW=$(mktemp)

REPOSITORY=${1:-"astral-sh/ruff"}

JQ_FILTER=\
'map(
  {
    "key": .tag_name,
    "value": .assets
        | map(select((.name | contains("ruff-")) and (.name | contains("sha256") | not) ))
        | map({
            "key": .name | capture("ruff-(?<platform>.*)\\.(tar\\.gz|zip)") | .platform,
            "value": (.browser_download_url + ".sha256"),
        })
        | from_entries
  }
) | from_entries'

SHA256_FILTER=\
'
map(
    select(.name == $tag)
    | .assets
    | map(.browser_download_url)[]
    | select(endswith(".sha256"))
)[]
'

gh api "repos/${REPOSITORY}/releases?per_page=1" > "$RELEASES"

jq "$JQ_FILTER" <$RELEASES >$RAW

# Combine the new versions with the existing ones.
# New versions should appear first, but existing content should overwrite new
CURRENT=$(mktemp)
python3 -c "import json; exec(open('$SCRIPT_DIR/ruff_versions.bzl').read()); print(json.dumps(RUFF_VERSIONS))" > $CURRENT
OUT=$(mktemp)
jq --slurp '.[0] * .[1]' $RAW $CURRENT > $OUT

FIXED=$(mktemp)
# Replace placeholder sha256 URLs with their content
for tag in $(jq -r 'keys | .[]' < $OUT); do
  # Download checksums for this tag
  # Note: this is wasteful; we will curl for sha256 files even if the CURRENT content already had resolved them
  for sha256url in $(jq --arg tag $tag -r "$SHA256_FILTER" < $RELEASES); do
    sha256=$(curl --silent --location $sha256url | awk '{print $1}')
    jq ".[\"$tag\"] |= with_entries(.value = (if .value == \"$sha256url\" then \"$sha256\" else .value end))" < $OUT > $FIXED
    mv $FIXED $OUT
  done
done

# Overwrite the file with updated content
(
  echo '"This file is automatically updated by mirror_ruff.sh"'
  echo -n "RUFF_VERSIONS = "
  cat $OUT
)>$SCRIPT_DIR/ruff_versions.bzl
