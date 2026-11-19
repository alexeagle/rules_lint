# How to Contribute

## Formatting

Starlark files should be formatted by buildifier.
We suggest using a pre-commit hook to automate this.
First [install pre-commit](https://pre-commit.com/#installation),
then run

```shell
pre-commit install
```

Otherwise later tooling on CI may yell at you about formatting/linting violations.

## Updating BUILD files

Some targets are generated from sources.
Currently this is just the `bzl_library` targets.
Run `aspect configure` to keep them up-to-date.

## Using this as a development dependency of other rules

You'll commonly find that you develop in another WORKSPACE, such as
some other ruleset that depends on rules_lint, or in a nested
WORKSPACE in the integration_tests folder.

To always tell Bazel to use this directory rather than some release
artifact or a version fetched from the internet, run this from this
directory:

```sh
OVERRIDE="--override_repository=rules_lint=$(pwd)/rules_lint"
echo "common $OVERRIDE" >> ~/.bazelrc
```

This means that any usage of `@rules_lint` on your system will point to this folder.

## Releasing

Release publishing and mirror pull requests use the organization-level
`BCR_PUBLISH_TOKEN` secret, owned by `bazel-contrib-bot`. This repository must
have access to that secret. The token needs write access to
`bazel-contrib/bazel-central-registry` for BCR publishing and to this
repository for mirror pull requests. BCR branches and pull request heads must
both point to the shared organization fork. Commit attribution is configured
explicitly in the workflows; the token determines the pull request author.

Releases are automated on a cron trigger.
If you do nothing, eventually the newest commits will be released automatically. See .github/workflows/tag.yaml.

To trigger a release where the new version can be determined automatically from the commit history, just navigate to
https://github.com/bazel-contrib/rules_lint/actions/workflows/tag.yaml
and press the "Run workflow" button.

If you need control over the next release version, for example when making a release candidate for a new major,
then: tag the repo and push the tag, for example

```sh
% git fetch
% git tag v1.0.0-rc0 origin/main
% git push origin v1.0.0-rc0
```

Then watch the automation run on GitHub actions which creates the release.

The Go linter's release path can be tested without publishing artifacts:

```shell
tools/release/test_go_prebuilts.sh
```

This builds native release binaries, stages a downstream consumer with the BCR
Go development-dependency patch applied, and runs the Go integration tests using
checksummed binaries from a local distribution directory. It also checks that
neither helper is built from source in the consumer.
