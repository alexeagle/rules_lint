#!/bin/bash

set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(dirname "$0")"
RUNFILES_DIR="$SCRIPT_DIR/cppcheck.runfiles"

# Find the cppcheck binary in the runfiles directory
# It will be under one of the cppcheck_* repositories. Searching all runfiles
# can select this wrapper's own _main/tools/lint/cppcheck entry and recurse.
# Note: cppcheck may be a symlink, so don't use -type f
CPPCHECK_BINARY=$(find "$RUNFILES_DIR" -path "$RUNFILES_DIR/*cppcheck_*/*" -name "cppcheck" \( -type f -o -type l \) 2>/dev/null | head -n1)

if [[ -z "$CPPCHECK_BINARY" ]]; then
    echo "Error: Could not find cppcheck binary in runfiles" >&2
    exit 1
fi

# cppcheck does not support config files.
# Instead options like --check-level can be added here:
"$CPPCHECK_BINARY" \
    --check-level=exhaustive \
    --enable=warning,style,performance,portability,information \
    "$@"

