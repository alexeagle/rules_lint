// Lint-clean source that includes C++ standard library headers.
// Exercises built-in include directory resolution: with -stdlib=libc++
// (from toolchains_llvm), clang-tidy must receive -isysroot pointing
// to the platform SDK so it can resolve system headers (wchar.h,
// stdlib.h, math.h) that libc++ depends on via #include_next.
// See: https://github.com/aspect-build/rules_lint/issues/566
#include <string>

namespace {
std::string greet(const std::string& name) {
    return "Hello, " + name + "!";
}
}  // namespace
