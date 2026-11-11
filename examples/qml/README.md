# QML Formatting and Linting Example

This example demonstrates how to set up formatting and linting for QML files using `rules_lint`.

## Supported Tools

### Formatters

- **qmlformat** - Qt's formatter for QML files

### Linters

- **qmllint** - Qt's linter for QML files

Both tools are invoked through the PySide wrappers `qmlformat` and `qmllint`.
The `qml` tag is used for both formatting and linting in this example.

On Linux, the PySide binaries require GLib (`libglib-2.0.so.0`) from the
system. On Ubuntu, install `libglib2.0-0`. The Python wheel bundles Qt
libraries but is not a fully static tool.

## Setup

1. Configure `MODULE.bazel` with `rules_python` and `rules_lint`
2. Configure the Aspect CLI lint task in `.aspect/config.axl`
3. Install PySide tool wrappers with `pip.parse`
4. Configure formatters and linters

- See `tools/format/BUILD` for how to set up the formatter
- See `tools/lint/linters.bzl` for how to set up the linter aspect

The linter example uses `.qmllint.ini` to promote `UnusedImports` from an informational diagnostic to a warning so the lint test fails on the sample file.

## Example Code

- `src/Main.qml` - QML file with formatting and lint violations

## Configuration Files

- `.qmlformat.ini` - qmlformat settings
- `.qmllint.ini` - qmllint warning settings
