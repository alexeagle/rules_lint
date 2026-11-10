# Python Formatting and Linting Example

This example demonstrates how to set up formatting and linting for Python code using `rules_lint`.

## Supported Tools

### Formatters

- **Ruff** - Fast Python linter and formatter (can be used for both linting and formatting)

### Linters

- **Ruff** - Fast Python linter (can catch many issues)
- **Pylint** - Comprehensive Python linter
- **Flake8** - Style guide enforcement
- **Pydoclint** - Docstring/signature consistency checks
- **Ty** - Type checker

## Setup

1. Configure MODULE.bazel with required dependencies
2. Configure the Aspect CLI lint task in `.aspect/config.axl`
3. Configure Formatters and Linters

- See `tools/format/BUILD` for how to set up the formatter
- See `tools/lint/linters.bzl` for how to set up each linter aspect

4. Perform formatting and linting using `aspect format` and `aspect lint`

## Example Code

The `src/` directory contains example Python files with intentional violations:

- `unused_import.py` - Contains unused import and format string violations
- `missing_doc_arg.py` - Contains a docstring/signature mismatch for pydoclint
- `unsupported_operator.py` - Contains type error (unsupported operator)
- `call_non_callable.py` - Contains call to non-callable (ignored in ty.toml)
- `uses_dependency.py` - Demonstrates transitive dependency linting

## Configuration Files

- `.ruff.toml` - Ruff configuration
- `src/ruff.toml` - Local Ruff configuration for src directory
- `src/subdir/ruff.toml` - Path-based Ruff configuration that ignores F401 (unused imports) in subdirectory
- `.pylintrc` - Pylint configuration
- `.flake8` - Flake8 configuration
- `pyproject.toml` - Bandit, Pydoclint, and Ty configuration

## Ty compatibility tests

Run `test/ty_compatibility.sh pinned` or `USE_BAZEL_VERSION=8.x test/ty_compatibility.sh 2.5.0-rc0` from this directory. The RC uses a checksummed release archive through a temporary module override and requires `flag_alias`, which is unavailable in the repository's Bazel 7.6.0 pin. Both commands preserve `MODULE.bazel` and run `//test:ty_compatibility_tests`, which CI exercises with Bazel 8.

The suite checks direct and transitive type-only imports, specific negative type diagnostics, and the ordinary example's runtime behavior. Both versions exclude stubs from runfiles. The selected rules_python 1.8.1 still includes `.py` files reached through `pyi_deps`. The RC must exclude those files and imports too.
