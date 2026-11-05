"Define C++ linter aspects"

load("@rules_lint//lint:clang_tidy.bzl", "lint_clang_tidy_aspect")
load("@rules_lint//lint:cppcheck.bzl", "lint_cppcheck_aspect")
load("@rules_lint//lint:lint_test.bzl", "lint_test")

clang_tidy = lint_clang_tidy_aspect(
    binary = Label("//tools/lint:clang_tidy"),
    configs = [
        Label("//:.clang-tidy"),
        Label("//src/cpp/lib:get/.clang-tidy"),
    ],
    lint_target_headers = True,
    angle_includes_are_system = False,
    verbose = False,
)

clang_tidy_test = lint_test(aspect = clang_tidy)

cppcheck = lint_cppcheck_aspect(
    binary = Label("//tools/lint:cppcheck"),
    verbose = True,
)

cppcheck_test = lint_test(aspect = cppcheck)

# an example of setting up a different clang-tidy aspect with different
# options. This one uses a single global clang-tidy file
clang_tidy_global_config = lint_clang_tidy_aspect(
    binary = "@@//tools/lint:clang_tidy",
    global_config = "@@//:.clang-tidy",
    lint_target_headers = True,
    angle_includes_are_system = False,
    verbose = False,
)
