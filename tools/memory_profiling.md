# Analysis memory profiling

Bazel's [Starlark memory tracker](https://bazel.build/rules/performance#memory-profiling)
samples allocations and reports surviving objects after GC. `--memory_profile`
reports whole-JVM heap usage; `--starlark_cpu_profile` measures CPU, not memory.

Download the public Maven dependency `com.google.code.java-allocation-instrumenter:java-allocation-instrumenter:3.3.5`
and set `ALLOCATION_AGENT` to its absolute jar path. Version 3.3.4 from older
Bazel documentation cannot instrument Java 25: the server's `java.log` reports
`Unsupported class file major version 69`. Its output severely undercounts memory.
Upgrading the agent to 3.3.5 fixes this; changing Bazel versions alone might not
change the bundled JVM. Check the server log before trusting a profile.

Use the same startup flags on **every** command, including `dump`, or Bazel
restarts its server and loses the analyzed graph. In bash/zsh:

```sh
export ALLOCATION_AGENT=/absolute/path/java-allocation-instrumenter-3.3.5.jar
export USE_BAZEL_VERSION=9.3.3
memory_flags=(
  "--host_jvm_args=-javaagent:$ALLOCATION_AGENT"
  --host_jvm_args=-DRULE_MEMORY_TRACKER=1
)

# From the repository root.
cd examples/cpp
bazel "${memory_flags[@]}" build --nobuild --config=lint --lockfile_mode=off \
  //src/...
bazel "${memory_flags[@]}" dump --rules
bazel "${memory_flags[@]}" dump --skylark_memory=/tmp/cpp-memory.gz
pprof -top -cum /tmp/cpp-memory.gz
pprof -list=cppcheck_action /tmp/cpp-memory.gz
```

`go tool pprof` also works. `--nobuild` runs analysis without executing linters
or compilers. Keep the workload and flags identical for before/after runs. Avoid
`--discard_analysis_cache`; the dump needs the retained analysis graph. Profiles
include loading and dependency allocations as well as analysis. They estimate
live sampled memory, not total allocations, peak RSS, or execution memory.

For Python, use `examples/python` and `--config=lint //src/...`. For Java, use
`examples/java` with `--aspects=//tools/lint:linters.bzl%spotbugs //src/...`.

## Measured change

Local macOS arm64, Bazel 9.3.3, allocation agent 3.3.5, November 2026:

The measurements below added temporary `//_memory_profile/...` targets to the
example commands. The C++ workload had 100 libraries each exporting 20 include
directories, and 100 consumers sharing all those dependencies. The Java workload
had 100 libraries and 100 consumers sharing those dependencies. These workloads
were generated on demand and removed after profiling.

| C++ workload, both linter aspects | Before | After |
| --- | ---: | ---: |
| Total sampled Starlark live memory | 64.78 MiB | 7.77 MiB |
| Cumulative `cppcheck_action` | 57.01 MiB | 0.25 MiB |

The root cause was eager flattening of transitive include depsets and allocating
`-I`-prefixed strings separately for every target and both report actions.
Passing depsets directly to `Args.add_all(format_each = "-I%s")` defers expansion
until execution and preserves sharing during analysis. The scaled workload's
total drops about 88%; this is not a claim about every user's whole Bazel heap.
The six expanded linter commands for `//_memory_profile:target0` matched
byte-for-byte before and after, including cppcheck's text and XML commands.

Verification: all 14 `//lint/test:all` tests passed on Bazel 7.6.0. The new
analysis test covers include category order, transitive order, duplicate paths
across categories, paths containing spaces, source short paths, and both report
formats. Actual cppcheck execution on Bazel 8.9.0 produced text, SARIF, and XML
reports with the expected violation exit code 31. This required fixing the
example wrapper's runfiles search: it could select its own `_main` entry instead
of the external cppcheck binary. The combined C++ execution also encountered
clang-tidy SDK/header errors; its expanded arguments were unchanged by this fix.

Java and Python example profiles were also inspected. They showed no comparable
retained linter hotspot. Static follow-ups include SpotBugs' flattened classpaths,
ty's repeated import-path expansion, and clang-tidy's per-file compiler argument
lists. The small examples do not establish a measurable benefit for those changes.
