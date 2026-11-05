"""PSScriptAnalyzer linter aspect for the PowerShell example workspace."""

load("@rules_lint//lint:lint_test.bzl", "lint_test")
load("@rules_lint//lint:ps_script_analyzer.bzl", "lint_ps_script_analyzer_aspect")

ps_script_analyzer = lint_ps_script_analyzer_aspect(
    binary = Label("@pwsh//:pwsh"),
    psscriptanalyzer = Label("@psscriptanalyzer//:files"),
    converttosarif = Label("@converttosarif//:files"),
    config = Label("//:PSScriptAnalyzerSettings.psd1"),
)

ps_script_analyzer_test = lint_test(aspect = ps_script_analyzer)
