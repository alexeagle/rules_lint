#!/usr/bin/env bash
# Exercise Go linting as a downstream consumer of a published module, without
# uploading a release. Pass Bazel startup options as arguments if needed.
set -euo pipefail

cd "$(dirname "$0")/../.."
export USE_BAZEL_VERSION="${USE_BAZEL_VERSION:-$(head -n 1 .bazelversion)}"
case "$(uname -s)" in
Darwin) os=darwin ;;
Linux) os=linux ;;
*)
  echo "Unsupported test host: $(uname -s)" >&2
  exit 1
  ;;
esac
case "$(uname -m)" in
arm64 | aarch64) arch=arm64 ;;
x86_64) arch=amd64 ;;
*)
  echo "Unsupported test architecture: $(uname -m)" >&2
  exit 1
  ;;
esac

bazel "$@" build --lockfile_mode=off \
  "//tools/release:gopackagesdriver-${os}-${arch}" \
  "//tools/release:sarif_parser-${os}-${arch}"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/release" "$fixture/consumer" "$fixture/distdir"

# Match the distributed source tree: examples are not in release archives.
tar -cf - --exclude=.git --exclude='bazel-*' --exclude=examples . |
  tar -xf - -C "$fixture/release"
tar -cf - --exclude='bazel-*' -C examples/go . |
  tar -xf - -C "$fixture/consumer"
for tool in gopackagesdriver sarif_parser; do
  binary="$(bazel "$@" cquery --lockfile_mode=off --output=files "//tools/release:${tool}-${os}-${arch}")"
  cp "$binary" "$fixture/distdir/"
done

python3 - "$fixture" <<'PY'
import hashlib
import pathlib
import sys

fixture = pathlib.Path(sys.argv[1])
release = fixture / "release"
module = release / "MODULE.bazel"
module.write_text(module.read_text().replace("IS_RELEASE = False", "IS_RELEASE = True"))
(release / "tools/version.bzl").write_text('VERSION = "0.0.0-test"\nIS_PRERELEASE = False\n')
integrity = {
    binary.name: hashlib.sha256(binary.read_bytes()).hexdigest()
    for binary in (fixture / "distdir").iterdir()
}
(release / "tools/integrity.bzl").write_text(f"RELEASED_BINARY_INTEGRITY = {integrity!r}\n")
consumer_module = fixture / "consumer/MODULE.bazel"
consumer_module.write_text(consumer_module.read_text().replace('path = "../.."', 'path = "../release"'))
# The copied example no longer sits two levels below the repository root.
# Keep its Aspect definitions available to configs selected by the caller's rc.
consumer_rc = fixture / "consumer/.bazelrc"
consumer_rc.write_text(consumer_rc.read_text().replace(
    "%workspace%/../../.aspect/bazelrc", "%workspace%/../release/.aspect/bazelrc"
))
PY

cd "$fixture/consumer"
bazel "$@" test --lockfile_mode=off --distdir="$fixture/distdir" //test:all

# Neither Go helper may re-enter the consumer's source build graph.
bazel "$@" cquery --lockfile_mode=off --distdir="$fixture/distdir" \
  'deps(//test:all)' >"$fixture/deps.txt"
if grep -E 'rules_lint.*//(lint/private/gopackagesdriver_static|tools/sarif)' "$fixture/deps.txt"; then
  echo "Published Go linting unexpectedly builds helper tools from source" >&2
  exit 1
fi
