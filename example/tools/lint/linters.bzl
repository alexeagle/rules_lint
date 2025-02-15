"Define linter aspects"

load("@aspect_rules_lint//lint:buf.bzl", "lint_buf_aspect")
load("@aspect_rules_lint//lint:checkstyle.bzl", "lint_checkstyle_aspect")
load("@aspect_rules_lint//lint:clang_tidy.bzl", "lint_clang_tidy_aspect")
load("@aspect_rules_lint//lint:eslint.bzl", "lint_eslint_aspect")
load("@aspect_rules_lint//lint:flake8.bzl", "lint_flake8_aspect")
load("@aspect_rules_lint//lint:keep_sorted.bzl", "lint_keep_sorted_aspect")
load("@aspect_rules_lint//lint:ktlint.bzl", "lint_ktlint_aspect")
load("@aspect_rules_lint//lint:lint_test.bzl", "lint_test")
load("@aspect_rules_lint//lint:pmd.bzl", "lint_pmd_aspect")
load("@aspect_rules_lint//lint:ruff.bzl", "lint_ruff_aspect")
load("@aspect_rules_lint//lint:shellcheck.bzl", "lint_shellcheck_aspect")
load("@aspect_rules_lint//lint:spotbugs.bzl", "lint_spotbugs_aspect")
load("@aspect_rules_lint//lint:stylelint.bzl", "lint_stylelint_aspect")
load("@aspect_rules_lint//lint:vale.bzl", "lint_vale_aspect")

buf = lint_buf_aspect(
    config = Label("@//:buf.yaml"),
)

eslint = lint_eslint_aspect(
    binary = Label("@//tools/lint:eslint"),
    # ESLint will resolve the configuration file by looking in the working directory first.
    # See https://eslint.org/docs/latest/use/configure/configuration-files#configuration-file-resolution
    # We must also include any other config files we expect eslint to be able to locate, e.g. tsconfigs
    configs = [
        Label("@//:eslintrc"),
        Label("@//src:tsconfig"),
    ],
)

eslint_test = lint_test(aspect = eslint)

stylelint = lint_stylelint_aspect(
    binary = Label("@//tools/lint:stylelint"),
    config = Label("@//:stylelintrc"),
)

flake8 = lint_flake8_aspect(
    binary = Label("@//tools/lint:flake8"),
    config = Label("@//:.flake8"),
)

flake8_test = lint_test(aspect = flake8)

pmd = lint_pmd_aspect(
    binary = Label("@//tools/lint:pmd"),
    rulesets = [Label("@//:pmd.xml")],
)

pmd_test = lint_test(aspect = pmd)

checkstyle = lint_checkstyle_aspect(
    binary = "@@//tools/lint:checkstyle",
    config = "@@//:checkstyle.xml",
    configs = {
        "@@//:checkstyle.xml": "@@//src,@@//test",
        "@@//:checkstyle_subdir.xml": "@@//src/subdir",
    },
    data = ["@@//:checkstyle-suppressions.xml"],
)

checkstyle_test = lint_test(aspect = checkstyle)

ruff = lint_ruff_aspect(
    binary = "@multitool//tools/ruff",
    configs = [
        Label("@//:.ruff.toml"),
        Label("@//src/subdir:ruff.toml"),
    ],
)

ruff_test = lint_test(aspect = ruff)

shellcheck = lint_shellcheck_aspect(
    binary = "@multitool//tools/shellcheck",
    config = Label("@//:.shellcheckrc"),
)

shellcheck_test = lint_test(aspect = shellcheck)

vale = lint_vale_aspect(
    binary = Label("@//tools/lint:vale"),
    config = Label("@//:.vale.ini"),
    styles = Label("@//tools/lint:vale_styles"),
)

ktlint = lint_ktlint_aspect(
    binary = Label("@com_github_pinterest_ktlint//file"),
    editorconfig = Label("@//:.editorconfig"),
    baseline_file = Label("@//:ktlint-baseline.xml"),
)

ktlint_test = lint_test(aspect = ktlint)

clang_tidy = lint_clang_tidy_aspect(
    binary = "@@//tools/lint:clang_tidy",
    configs = [
        "@@//:.clang-tidy",
        "@@//src/cpp/lib:get/.clang-tidy",
    ],
    lint_target_headers = True,
    angle_includes_are_system = False,
    verbose = False,
)

clang_tidy_test = lint_test(aspect = clang_tidy)

# an example of setting up a different clang-tidy aspect with different
# options. This one uses a single global clang-tidy file
clang_tidy_global_config = lint_clang_tidy_aspect(
    binary = "@@//tools/lint:clang_tidy",
    global_config = "@@//:.clang-tidy",
    lint_target_headers = True,
    angle_includes_are_system = False,
    verbose = False,
)

spotbugs = lint_spotbugs_aspect(
    binary = Label("@//tools/lint:spotbugs"),
    exclude_filter = Label("@//:spotbugs-exclude.xml"),
)

spotbugs_test = lint_test(aspect = spotbugs)

keep_sorted = lint_keep_sorted_aspect(
    binary = Label("@com_github_google_keep_sorted//:keep-sorted"),
)

keep_sorted_test = lint_test(aspect = keep_sorted)
