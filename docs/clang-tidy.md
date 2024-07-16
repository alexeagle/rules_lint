<!-- Generated with Stardoc: http://skydoc.bazel.build -->

API for calling declaring a clang-tidy lint aspect.

Typical usage:

First, install clang-tidy with llvm_toolchain or as a native binary (llvm_toolchain
does not support Windows as of 06/2024, but providing a native clang-tidy.exe works)

Next, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

e.g. using llvm_toolchain:
```starlark
native_binary(
    name = "clang_tidy",
    src = "@llvm_toolchain_llvm//:bin/clang-tidy"
    out = "clang_tidy",
)
```

e.g as native binary:
```starlark
native_binary(
    name = "clang_tidy",
    src = "clang-tidy.exe"
    out = "clang_tidy",
)
```

Finally, create the linter aspect, typically in `tools/lint/linters.bzl`:

```starlark
load("@aspect_rules_lint//lint:clang_tidy.bzl", "lint_clang_tidy_aspect")

clang_tidy = lint_clang_tidy_aspect(
    binary = "@@//path/to:clang-tidy",
    configs = "@@//path/to:.clang-tidy",
)
```


<a id="clang_tidy_action"></a>

## clang_tidy_action

<pre>
clang_tidy_action(<a href="#clang_tidy_action-ctx">ctx</a>, <a href="#clang_tidy_action-compilation_context">compilation_context</a>, <a href="#clang_tidy_action-executable">executable</a>, <a href="#clang_tidy_action-srcs">srcs</a>, <a href="#clang_tidy_action-stdout">stdout</a>, <a href="#clang_tidy_action-exit_code">exit_code</a>)
</pre>

Create a Bazel Action that spawns a clang-tidy process.

Adapter for wrapping Bazel around
https://clang.llvm.org/extra/clang-tidy/


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="clang_tidy_action-ctx"></a>ctx |  an action context OR aspect context   |  none |
| <a id="clang_tidy_action-compilation_context"></a>compilation_context |  from target   |  none |
| <a id="clang_tidy_action-executable"></a>executable |  struct with a clang-tidy field   |  none |
| <a id="clang_tidy_action-srcs"></a>srcs |  file objects to lint   |  none |
| <a id="clang_tidy_action-stdout"></a>stdout |  output file containing the stdout or --output-file of clang-tidy   |  none |
| <a id="clang_tidy_action-exit_code"></a>exit_code |  output file containing the exit code of clang-tidy. If None, then fail the build when clang-tidy exits non-zero.   |  none |


<a id="clang_tidy_fix"></a>

## clang_tidy_fix

<pre>
clang_tidy_fix(<a href="#clang_tidy_fix-ctx">ctx</a>, <a href="#clang_tidy_fix-compilation_context">compilation_context</a>, <a href="#clang_tidy_fix-executable">executable</a>, <a href="#clang_tidy_fix-srcs">srcs</a>, <a href="#clang_tidy_fix-patch">patch</a>, <a href="#clang_tidy_fix-stdout">stdout</a>, <a href="#clang_tidy_fix-exit_code">exit_code</a>)
</pre>

Create a Bazel Action that spawns clang-tidy with --fix.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="clang_tidy_fix-ctx"></a>ctx |  an action context OR aspect context   |  none |
| <a id="clang_tidy_fix-compilation_context"></a>compilation_context |  from target   |  none |
| <a id="clang_tidy_fix-executable"></a>executable |  struct with a clang_tidy field   |  none |
| <a id="clang_tidy_fix-srcs"></a>srcs |  list of file objects to lint   |  none |
| <a id="clang_tidy_fix-patch"></a>patch |  output file containing the applied fixes that can be applied with the patch(1) command.   |  none |
| <a id="clang_tidy_fix-stdout"></a>stdout |  output file containing the stdout or --output-file of clang-tidy   |  none |
| <a id="clang_tidy_fix-exit_code"></a>exit_code |  output file containing the exit code of clang-tidy   |  none |


<a id="is_parent_in_list"></a>

## is_parent_in_list

<pre>
is_parent_in_list(<a href="#is_parent_in_list-dir">dir</a>, <a href="#is_parent_in_list-list">list</a>)
</pre>



**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="is_parent_in_list-dir"></a>dir |  <p align="center"> - </p>   |  none |
| <a id="is_parent_in_list-list"></a>list |  <p align="center"> - </p>   |  none |


<a id="lint_clang_tidy_aspect"></a>

## lint_clang_tidy_aspect

<pre>
lint_clang_tidy_aspect(<a href="#lint_clang_tidy_aspect-binary">binary</a>, <a href="#lint_clang_tidy_aspect-name">name</a>, <a href="#lint_clang_tidy_aspect-configs">configs</a>, <a href="#lint_clang_tidy_aspect-global_config">global_config</a>, <a href="#lint_clang_tidy_aspect-header_filter">header_filter</a>, <a href="#lint_clang_tidy_aspect-lint_target_headers">lint_target_headers</a>,
                       <a href="#lint_clang_tidy_aspect-angle_includes_are_system">angle_includes_are_system</a>, <a href="#lint_clang_tidy_aspect-verbose">verbose</a>, <a href="#lint_clang_tidy_aspect-mnemonic_suffix">mnemonic_suffix</a>)
</pre>

A factory function to create a linter aspect.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="lint_clang_tidy_aspect-binary"></a>binary |  the clang-tidy binary, typically a rule like<br><br><pre><code>starlark native_binary(     name = "clang_tidy",     src = "clang-tidy.exe"     out = "clang_tidy", ) </code></pre>   |  none |
| <a id="lint_clang_tidy_aspect-name"></a>name |  name of the aspect.   |  <code>"clang-tidy"</code> |
| <a id="lint_clang_tidy_aspect-configs"></a>configs |  labels of the .clang-tidy files to make available to clang-tidy's config search. These may be in subdirectories and clang-tidy will apply them if appropriate. This may also include .clang-format files which may be used for formatting fixes.   |  <code>[]</code> |
| <a id="lint_clang_tidy_aspect-global_config"></a>global_config |  label of a single global .clang-tidy file to pass to clang-tidy on the command line. This will cause clang-tidy to ignore any other config files in the source directories.   |  <code>[]</code> |
| <a id="lint_clang_tidy_aspect-header_filter"></a>header_filter |  optional, set to a posix regex to supply to clang-tidy with the -header-filter option   |  <code>""</code> |
| <a id="lint_clang_tidy_aspect-lint_target_headers"></a>lint_target_headers |  optional, set to True to pass a pattern that includes all headers with the target's directory prefix. This crude control may include headers from the linted target in the results. If supplied, overrides the header_filter option.   |  <code>False</code> |
| <a id="lint_clang_tidy_aspect-angle_includes_are_system"></a>angle_includes_are_system |  controls how angle includes are passed to clang-tidy. By default, Bazel passes these as -isystem. Change this to False to pass these as -I, which allows clang-tidy to regard them as regular header files.   |  <code>True</code> |
| <a id="lint_clang_tidy_aspect-verbose"></a>verbose |  print debug messages including clang-tidy command lines being invoked.   |  <code>False</code> |
| <a id="lint_clang_tidy_aspect-mnemonic_suffix"></a>mnemonic_suffix |  suffix of mnemonic to be used. A prefix of AspectRulesLint is always used.   |  <code>"ClangTidy"</code> |


