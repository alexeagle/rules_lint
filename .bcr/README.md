# Bazel Central Registry

When the ruleset is released, we want it to be published to the
Bazel Central Registry automatically:
<https://registry.bazel.build>

This folder contains configuration files to automate the publish step.
See <https://github.com/bazel-contrib/publish-to-bcr/blob/main/templates/README.md>
for authoritative documentation about these files.

This repo hosts several separately versioned modules. Each module's templates
live under this folder at the same relative path as the module in the repo:

- `.bcr/` — the root `rules_lint` module, released from `v*` tags
- `.bcr/lint/rust/` — the `rules_lint_rust` module (`lint/rust`),
  released from `rust-v*` tags
- `.bcr/lint/scala/` — the `rules_lint_scala` module (`lint/scala`),
  released from `scala-v*` tags

Each release publishes exactly one module: the trigger workflow passes the
module's root through the `module_roots` input of the publish-to-bcr reusable
workflow (see `.github/workflows/release-module.yaml`).
