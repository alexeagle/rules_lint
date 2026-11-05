"Define Java linter aspects"

load("@rules_lint//lint:checkstyle.bzl", "lint_checkstyle_aspect")
load("@rules_lint//lint:lint_test.bzl", "lint_test")
load("@rules_lint//lint:pmd.bzl", "lint_pmd_aspect")
load("@rules_lint//lint:spotbugs.bzl", "lint_spotbugs_aspect")

pmd = lint_pmd_aspect(
    binary = Label("//tools/lint:pmd"),
    rulesets = [Label("//:pmd.xml")],
)

pmd_test = lint_test(aspect = pmd)

checkstyle = lint_checkstyle_aspect(
    binary = Label("//tools/lint:checkstyle"),
    config = Label("//:checkstyle.xml"),
    data = [Label("//:checkstyle-suppressions.xml")],
)

checkstyle_test = lint_test(aspect = checkstyle)

spotbugs = lint_spotbugs_aspect(
    binary = Label("//tools/lint:spotbugs"),
    exclude_filter = Label("//:spotbugs-exclude.xml"),
)

spotbugs_test = lint_test(aspect = spotbugs)
