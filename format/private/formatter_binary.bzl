"Utilities for format_multirun macro"

# Per the formatter design, each language can only have a single formatter binary
# Keys in this map must match the `case "$language" in` block in format.sh
TOOLS = {
    # NB: includes TypeScript and some others
    "JavaScript": "prettier",
    "Markdown": "prettier",
    # NB: includes LESS and SASS
    "CSS": "prettier",
    "CUE": "cue-fmt",
    "GraphQL": "prettier",
    "HTML": "prettier",
    "Python": "ruff",
    "QML": "qmlformat",
    "Starlark": "buildifier",
    "Jsonnet": "jsonnetfmt",
    "Terraform": "terraform-fmt",
    "TOML": "taplo",
    "Kotlin": "ktfmt",
    "Java": "java-format",
    "HTML Jinja": "djlint",
    "Scala": "scalafmt",
    "Swift": "swiftformat",
    "Go": "gofmt",
    "SQL": "prettier",
    "Shell": "shfmt",
    "Protocol Buffer": "buf",
    "C": "clang-format",
    "C++": "clang-format",
    "Cuda": "clang-format",
    "YAML": "yamlfmt",
    "Rust": "rustfmt",
    "Ruby": "stree",
    "XML": "prettier",
    "Gherkin": "prettier",
    "F#": "fantomas",
    "C#": "csharpier",
    "Pkl": "pkl",
    "Go Module": "modfmt",
}

# Provided to make install more convenient
BUILTIN_TOOL_LABELS = {
    "CUE": "@multitool//tools/cue",
    "Jsonnet": "@multitool//tools/jsonnetfmt",
    "Go": "@multitool//tools/gofumpt",
    "Shell": "@multitool//tools/shfmt",
    "Terraform": "@multitool//tools/terraform",
    "YAML": "@multitool//tools/yamlfmt",
    "Python": "@multitool//tools/ruff",
}

# Flags to pass each tool's CLI when running in check mode
CHECK_FLAGS = {
    "buildifier": "-mode=check",
    "cue-fmt": "fmt --check",
    "swiftformat": "--lint",
    "prettier": "--check --log-level=warn",
    "ruff": "format --check --force-exclude --diff",
    "qmlformat": "",
    "shfmt": "--diff --apply-ignore",
    "java-format": "--set-exit-if-changed --dry-run",
    "djlint": "--format-css --format-js --check",
    "ktfmt": "--set-exit-if-changed --dry-run",
    "gofmt": "-l",
    "buf": "format -d --exit-code --disable-symlinks",
    "taplo": "format --check --diff",
    "terraform-fmt": "fmt -check -diff",
    "jsonnetfmt": "--test",
    "scalafmt": "--test --respect-project-filters",
    "clang-format": "--style=file --fallback-style=none --dry-run -Werror",
    "yamlfmt": "-lint",
    "rustfmt": "--check",
    "stree": "check",
    "fantomas": "--check",
    "csharpier": "check",
    "pkl": "format --silent",
    "modfmt": "-c",
}

# Flags to pass each tool when running in default mode
FIX_FLAGS = {
    "buildifier": "-mode=fix",
    "cue-fmt": "fmt",
    "djlint": "--format-css --format-js --reformat",
    "swiftformat": "",
    "prettier": "--write --log-level=warn",
    # Force exclusions in the configuration file to be honored even when file paths are supplied
    # as command-line arguments; see
    # https://github.com/astral-sh/ruff/discussions/5857#discussioncomment-6583943
    "ruff": "format --force-exclude",
    "qmlformat": "--inplace",
    # NB: apply-ignore added in https://github.com/mvdan/sh/issues/1037
    "shfmt": "-w --apply-ignore",
    "java-format": "--replace",
    "ktfmt": "",
    "gofmt": "-w",
    "buf": "format --write --disable-symlinks",
    "taplo": "format",
    "terraform-fmt": "fmt",
    "jsonnetfmt": "--in-place",
    # Force exclusions in the configuration file to be honored even when file paths are supplied
    # as command-line arguments; see
    # https://github.com/scalameta/scalafmt/pull/2020
    "scalafmt": "--respect-project-filters",
    "clang-format": "-style=file --fallback-style=none -i",
    "yamlfmt": "",
    "rustfmt": "",
    "stree": "write",
    "fantomas": "",
    "csharpier": "format",
    "pkl": "format --write",
    "modfmt": "-w",
}

def to_attribute_name(lang):
    """Convert a language name to the corresponding attribute name in the formatter rule.

    Args:
        lang: The human-readable language name, e.g. "C++" or "F#".

    Returns:
        The corresponding attribute name in the formatter rule.
    """
    if lang == "C++":
        return "cc"
    if lang == "C#":
        return "csharp"
    if lang == "F#":
        return "fsharp"
    return lang.lower().replace(" ", "_")
