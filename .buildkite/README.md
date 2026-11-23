# Buildkite CI

Set the pipeline's steps to the contents of [pipeline.yml](pipeline.yml).
The setup job needs Python 3.9+ and `buildkite-agent`; generated jobs need
Git and Docker on a Linux agent. Jobs use the pipeline's default queue except
Node.js, which requires a `linux-medium` hosted queue (4 vCPU, 16 GB RAM).
Oxlint's JS-plugin bridge reserves a large arena per worker even for tiny files;
the larger host preserves the plugin and multi-pass autofix demonstration while
[the upstream allocator bug](https://github.com/oxc-project/oxc/issues/20331)
remains open. The example caps Oxlint at one worker per invocation and serializes
Bazel CI actions so multiple arena reservations do not compete for host memory.
The checkout must be accessible to the Docker daemon for the bind mount.

The pipeline discovers `examples/**/tools/format`, `examples/**/tools/lint`,
and `examples/**/test/**/*.bats`. Two groups run concurrently after setup:

- **Examples**: one job per example, exercising both Bazel and Aspect CLI
  format/lint entry points, plus Bats where enabled.
- **Ruleset tests**: root Bazel tests on 7.x, 8.x, and 9.x, plus `format/test`.
  Non-test targets are built too; release-only targets are tagged `manual`
  to avoid building binaries for other platforms.

GitHub Actions retains macOS Java and C++ checks, Go workspace and published-tool
compatibility, Python dependency compatibility, BCR patch validation, link
checking, and release automation. Its `test-all`
check covers only those remaining CI jobs; require the Buildkite pipeline's
status separately in branch protection.

Each job builds [Dockerfile](Dockerfile), which pins the Aspect launcher,
Bazelisk, and Bats tools. The launcher reads the shared `.aspect/version.axl`
version pin. `docker build --load` supports remote BuildKit drivers by
exporting the image to the local Docker daemon. Each job removes its image
tag on exit, including after failures. Tests run as a non-root user
because rules_python's hermetic interpreter refuses root execution.

The container uses Ubuntu 22.04 for the pinned clang-format's `libtinfo5`
dependency. Bazel 8 exceptions and disabled Bats suites remain recorded in
[pipeline.py](pipeline.py); these predate the migration.

Commands run in a disposable clone and restore fixtures before each check:
examples intentionally contain lint and format violations. Checks continue
after failures to report all results. Bazel/Aspect wrappers also apply inside
Bats, closing its TAP descriptor so Bazel servers cannot keep the suite open.
The Aspect wrapper disables remote services, uploads, and reporting.
The image installs [ci.bazelrc](ci.bazelrc) as `/etc/bazel.bazelrc`, so all
Bazel invocations load the shared CI settings automatically; workspace rc
files still apply.

Preview the pipeline and test discovery/runner behavior locally:

```sh
.buildkite/pipeline.py
python3 -m unittest discover -s .buildkite -p 'test_*.py'
```
