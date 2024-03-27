# Formatting

## Installation

Create a BUILD file that declares the formatter binary, typically at `tools/format/BUILD.bazel`

Each formatter should be installed in your repository, see our `example/tools/format/BUILD.bazel` file.
A formatter is just an executable target.

Then register them on the `formatters` attribute, for example:

```starlark
load("@aspect_rules_lint//format:defs.bzl", "format_multirun")

format_multirun(
    name = "format",
    # register languages, e.g.
    # python = "//:ruff",
)
```

Finally, we recommend an alias in the root BUILD file, so that developers can just type `bazel run format`:

```starlark
alias(
    name = "format",
    actual = "//tools/format",
)
```

## Usage

### Configuring formatters

Since the `format` target is a `bazel run` command, it already runs in the working directory alongside the sources.
Therefore the configuration instructions for the formatting tool should work as-is.
Whatever configuration files the formatter normally discovers will be used under Bazel as well.

As an example, if you want to change the indent level for Shell formatting, you can follow the
[instructions for shfmt](https://github.com/mvdan/sh/blob/master/cmd/shfmt/shfmt.1.scd#examples) and create a `.editorconfig` file: 

```
[[shell]]
indent_style = space
indent_size = 4
```

### One-time re-format all files

Assuming you installed with the typical layout:

`bazel run //:format`

> Note that mass-reformatting can be disruptive in an active repo.
> You may want to instruct developers with in-flight changes to reformat their branches as well, to avoid merge conflicts.
> Also consider adding your re-format commit to the
> [`.git-blame-ignore-revs` file](https://docs.github.com/en/repositories/working-with-files/using-files/viewing-a-file#ignore-commits-in-the-blame-view)
> to avoid polluting the blame layer.

### Re-format specific file(s)

`bazel run //:format some/file.md other/file.json`

### Install as a pre-commit hook

If you use [pre-commit.com](https://pre-commit.com/), add this in your `.pre-commit-config.yaml`:

```yaml
- repo: local
  hooks:
    - id: aspect_rules_lint
      name: Format
      language: system
      entry: bazel run //:format
      files: .*
```

> Note that pre-commit is silent while Bazel is fetching the tooling, which can make it appear hung on the first run.
> There is no way to avoid this; see https://github.com/pre-commit/pre-commit/issues/1003

If you don't use pre-commit, you can just wire directly into the git hook, however
this option will always run the formatter over all files, not just changed files.

```bash
$ echo "bazel run //:format.check" >> .git/hooks/pre-commit
$ chmod u+x .git/hooks/pre-commit
```

### Check that files are already formatted

This will exit non-zero if formatting is needed. You would typically run the check mode on CI.

`bazel run //tools/format:format.check`
