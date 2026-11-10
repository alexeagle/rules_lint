# Examples

This directory contains self-contained examples demonstrating how to use `rules_lint` for formatting, linting, or both.

Each example includes a minimal working configuration for its supported tools. From an example directory, run `aspect format` for formatting or `aspect lint //...` for linting when the corresponding tool is configured.

## Available Examples

| Directory           | Formatter(s)                                                                  | Linter(s)                                   |
| ------------------- | ----------------------------------------------------------------------------- | ------------------------------------------- |
| `cpp/`              | clang-format for C, C++, and CUDA                                             | clang-tidy, Cppcheck                        |
| `csharp/`           | CSharpier                                                                     |                                             |
| `fsharp/`           | Fantomas                                                                      |                                             |
| `go-module/`        | modfmt                                                                        |                                             |
| `go/`               | gofumpt                                                                       |                                             |
| `java/`             | google-java-format                                                            | PMD, Checkstyle, SpotBugs                   |
| `keep-sorted/`      |                                                                               | keep-sorted                                 |
| `kotlin/`           | ktfmt                                                                         | ktlint                                      |
| `nodejs/`           | Prettier for JavaScript, TypeScript, Vue, CSS, Less, SCSS, HTML, and Markdown | ESLint, Stylelint, Vale                     |
| `nix/`              | nixfmt                                                                        |                                             |
| `other_formatters/` | cue fmt, Prettier, jsonnetfmt, djlint                                         |                                             |
| `pkl/`              | pkl format                                                                    |                                             |
| `protobuf/`         | Buf                                                                           | Buf                                         |
| `python/`           | Ruff                                                                          | Ruff, Bandit, Flake8, pydoclint, Pylint, ty |
| `qml/`              | qmlformat                                                                     | qmllint                                     |
| `ruby/`             |                                                                               | RuboCop, StandardRB                         |
| `rust/`             | rustfmt                                                                       | Clippy                                      |
| `scala/`            | Scalafmt                                                                      | Scalafix                                    |
| `shell/`            | shfmt                                                                         | ShellCheck                                  |
| `sql/`              | Prettier with its SQL plugin                                                  |                                             |
| `starlark/`         |                                                                               | Buildifier                                  |
| `swift/`            | SwiftFormat                                                                   |                                             |
| `terraform/`        | terraform fmt                                                                 |                                             |
| `toml/`             | Taplo                                                                         | Taplo                                       |
| `xml/`              | Prettier with its XML plugin                                                  |                                             |
| `yaml/`             | yamlfmt                                                                       | yamllint                                    |

The `other_formatters/` example covers CUE, Gherkin, GraphQL, HTML Jinja templates, JSON5, and Jsonnet without creating a separate workspace for each format.
