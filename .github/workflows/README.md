# Mirror Releases access

`mirror.yml` uses `BCR_PUBLISH_TOKEN` to push dependency updates and open a
pull request. Its owner, `bazel-contrib-bot`, needs **Write** access to this
repository, and the token needs contents and pull request write permissions.
The bot token lets the resulting pull request trigger GitHub Actions checks.

After transferring the repository, verify the bot's access in the destination
organization and that the token authorizes the transferred repository.

The failed [mirror run](https://github.com/bazel-contrib/rules_lint/actions/runs/44916479690/job/136883073182)
reported `Permission to bazel-contrib/rules_lint.git denied to bazel-contrib-bot`.
The bot had only Read access. Restore Write access, then rerun the failed job.
Changing workflow `permissions` does not grant access to this separate bot token.

Release metadata and asset downloads use `gh` with the workflow's read-only
`github.token`. The Ruff mirror uses the same authentication. Multitool v0.9.0
makes anonymous release requests and panics when GitHub returns a rate-limit
error instead of a release. `update_multitool.py` replaces that updater, validates
asset names against the release, verifies downloaded checksums, and waits until
both lockfiles have valid updates before writing either file.

Jsonnet v0.22.0 changed asset names from `go-jsonnet_Linux_x86_64.tar.gz` to
`go-jsonnet_0.22.0_linux_amd64.tar.gz` (with equivalent changes on other platforms).
The lockfile records the new names so future version substitutions work.

Run updater tests with:

```sh
python3 -m unittest discover -s .github/workflows -p 'test_*.py'
```
