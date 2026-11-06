load("@aspect_rules_js//js:defs.bzl", "js_library")
load("@aspect_rules_ts//ts:defs.bzl", "ts_config", "ts_project")
load("//tools/lint:linters.bzl", "oxlint_typed_test")

package(default_visibility = ["//visibility:public"])

ts_config(
    name = "oxlint_tsconfig_base",
    src = "tsconfig-base.json",
)

js_library(
    name = "oxlint_promise",
    srcs = ["promise.d.ts"],
)

ts_project(
    name = "typed",
    srcs = ["index.ts"],
    declaration = True,
    extends = ":oxlint_tsconfig_base",
    transpiler = "tsc",
    tsconfig = "tsconfig.json",
    deps = [":oxlint_promise"],
)

oxlint_typed_test(
    name = "typed_test",
    srcs = [":typed"],
    expected_exit_code = 1,
)
