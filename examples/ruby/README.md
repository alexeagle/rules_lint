# Ruby Formatting and Linting Example

This example demonstrates how to set up formatting and linting for Ruby code using `rules_lint`.

## Supported Tools

### Linters

- **RuboCop** - Ruby static code analyzer
- **Standard Ruby** - Zero-configuration Ruby style guide and linter based on RuboCop

### Formatter

- **Syntax Tree (`stree`)** - Formats `.rb` and `.rake` files through the `ruby`
  attribute of `format_multirun`. The default arguments are `check` and `write`.

### Formatting setup

[MODULE.bazel](MODULE.bazel) fetches a separate, checksum-pinned bundle containing
Syntax Tree 6.2.0 and prettier_print 1.2.1, using the formatter's
[Gemfile](tools/format/Gemfile) and [lockfile](tools/format/Gemfile.lock).
[tools/format/BUILD](tools/format/BUILD) declares the executable and registers it
with `format_multirun`.

The [CLI patch](tools/format/syntax-tree-cli.patch) fixes two integration issues:
the Ruby launcher starts in runfiles, so stree must restore the invoking directory
to resolve source paths and `.streerc`; symlink aliases can bypass exclusions and
write into ignored targets, so stree skips symlink inputs. The bundle's `patches`
attribute applies this patch after bundle installation. Since rules_ruby 0.21.1
has no gem-patch attribute, a small [rules_ruby patch](tools/format/rules-ruby-gem-patches.patch)
adds it through `single_version_override`. Applying gem patches requires the Unix
`patch` command (Linux or macOS).

Run from this example's directory:

```sh
bazel run //tools/format
bazel run //tools/format:format.check
# Limit formatting to selected files:
bazel run //tools/format -- src/hello.rb
```

Supply a `.streerc` to configure project style and exclusions. This example's
[.streerc](.streerc) sets width 100 and enables trailing commas:

```text
--print-width=100
--plugins=plugin/trailing_comma
```

Use `ruby_check_args` and `ruby_fix_args` to replace CLI arguments when needed;
include the `check` or `write` subcommand. See [formatting setup](../../docs/formatting.md).

## Setup

1. Configure MODULE.bazel with required dependencies
2. Configure the Aspect CLI lint task in `.aspect/config.axl`
3. Configure Linters

- See `tools/lint/linters.bzl` for how to set up each linter aspect

4. Perform linting using `aspect lint`

## Example Code

The `src/` directory contains example Ruby files with intentional violations:

- `hello.rb` - Contains RuboCop and Standard Ruby violations (unused variables, line length, indentation, string literals, trailing commas)

## Configuration Files

- `.streerc` - Syntax Tree formatting configuration
- `.rubocop.yml` - RuboCop configuration
- `.standard.yml` - Standard Ruby configuration
- `Gemfile` - Ruby gem dependencies
- `.ruby-version` - Ruby version specification
