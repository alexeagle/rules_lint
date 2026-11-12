# Go Formatting and Linting Example

This example demonstrates Go formatting and hermetic, per-package golangci-lint actions using `rules_lint`.

## Supported Tools

### Formatters

- **gofumpt** - Stricter version of gofmt with additional formatting rules

Note: You can also use standard `gofmt` instead of `gofumpt` if you prefer.

## Setup

1. Configure `MODULE.bazel` with the required dependencies
2. Configure the formatter

- See `tools/format/BUILD` for how to set up the formatter

3. Perform formatting using `aspect format`

## Example Code

See `src/hello.go` for a simple example Go program.

## golangci-lint

Requires rules_go 0.61.0 or newer so package metadata includes cgo outputs for
test archives. Run `bazel build --config=lint //src:all` to lint, or
`bazel test //test:all` to check both exit codes and diagnostic content.

Dependency sources remain available to compute cross-package analyzer facts.
Compiler export data alone cannot supply those facts. Only the selected root
package is a lint target; dependencies may be analyzed to produce facts. Each
action starts with a private empty cache, so dependency analysis can repeat
across lint actions. Bazel still caches each action's complete result.

The `test/analyzerfacts` fixture checks a format error through `relay.Relay`,
whose name does not identify it as a printf wrapper. The expected diagnostic
matches native golangci-lint 2.12.2, including its line and column. A deliberate
`bools` finding in the dependency checks that dependency diagnostics stay out of
the root report. The clean consumer checks the valid call too.
