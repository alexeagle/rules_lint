#!/usr/bin/env bash
# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

# Test script to verify that custom arguments are correctly embedded in generated multirun configuration

set -o nounset -o errexit -o pipefail

echo "Testing custom arguments in generated multirun configuration..."

check_flags() {
    local script_name="$1"
    local expected_flags="$2"
    local description="$3"
    
    script_path="$(rlocation "_main/format/test/$script_name")"
    if [[ ! -f "$script_path" ]]; then
        echo "✗ $description: script not found"
        exit 1
    fi
    
    if grep -q "export flags='$expected_flags'" "$script_path"; then
        echo "✓ $description"
    else
        echo "✗ $description"
        exit 1
    fi
}

# Test custom arguments work
check_flags "format_with_custom_args_Kotlin_with_ktfmt.bash" "--custom-fix --flag" "Kotlin fix mode has custom arguments"
check_flags "format_with_custom_args_Kotlin_with_ktfmt.check.bash" "--custom-check" "Kotlin check mode has custom arguments"

# Test default arguments used when no custom specified
check_flags "format_with_custom_args_Java_with_java-format.check.bash" "--set-exit-if-changed --dry-run" "Java check mode uses default arguments"

check_flags "format_Ruby_with_stree.bash" "write" "Ruby fix mode uses stree defaults"
check_flags "format_Ruby_with_stree.check.bash" "check" "Ruby check mode uses stree defaults"
check_flags "format_with_custom_args_Ruby_with_stree.bash" "write --print-width=80" "Ruby fix mode has custom arguments"
check_flags "format_with_custom_args_Ruby_with_stree.check.bash" "check --print-width=80" "Ruby check mode has custom arguments"

echo "All custom arguments tests passed!"
