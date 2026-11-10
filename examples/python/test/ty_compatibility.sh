#!/usr/bin/env bash
set -euo pipefail

version="${1:-pinned}"
if (($#)); then shift; fi
example="$(cd "$(dirname "$0")/.." && pwd)"
cd "$example"

case "$version" in
  pinned) legacy_sources=1 ;;
  2.5.0-rc0)
    legacy_sources=0
    temporary="$(mktemp -d)"
    trap 'rm -rf "$temporary"' EXIT
    curl --fail --location --retry 3 \
      "https://github.com/bazel-contrib/rules_python/releases/download/$version/rules_python-$version.tar.gz" \
      --output "$temporary/rules_python.tar.gz"
    printf '%s  %s\n' \
      '2bf5f5ff0be99bf9f6e02ab4086848a181c9093a09e04719ab80bc27a59d7645' \
      "$temporary/rules_python.tar.gz" | shasum -a 256 -c
    tar -xzf "$temporary/rules_python.tar.gz" -C "$temporary"
    set -- "--override_module=rules_python=$temporary/rules_python-$version" "$@"
    ;;
  *) echo "Usage: $0 [pinned|2.5.0-rc0] [bazel test flags...]" >&2; exit 2 ;;
esac

# Keep the example's selected version and the user's Bazel configuration intact.
bazel --nosystem_rc --nohome_rc test "$@" \
  --test_env=TY_EXPECT_LEGACY_PYI_SOURCES="$legacy_sources" \
  //test:ty_compatibility_tests
