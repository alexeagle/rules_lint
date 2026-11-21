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
