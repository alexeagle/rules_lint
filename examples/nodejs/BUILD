load("@aspect_rules_js//js:defs.bzl", "js_library")
load("@npm//:defs.bzl", "npm_link_all_packages")

package(default_visibility = ["//visibility:public"])

npm_link_all_packages(name = "node_modules")

exports_files(
    [
        ".oxlintrc.json",
        ".swcrc",
        ".vale.ini",
    ],
    visibility = ["//visibility:public"],
)

js_library(
    name = "eslintrc",
    srcs = ["eslint.config.mjs"],
    deps = [
        ":node_modules/@eslint/js",
        ":node_modules/typescript-eslint",
    ],
)

js_library(
    name = "stylelintrc",
    srcs = ["stylelint.config.mjs"],
    deps = [":node_modules/stylelint-config-standard"],
)

js_library(
    name = "prettierrc",
    srcs = ["prettier.config.cjs"],
)
