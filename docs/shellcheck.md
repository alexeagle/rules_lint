<!-- Generated with Stardoc: http://skydoc.bazel.build -->

API for declaring a shellcheck lint aspect that visits sh_library rules.

Typical usage:

1. Use [fetch_shellcheck](#fetch_shellcheck) in WORKSPACE to call the `http_archive` calls to download binaries.
2. Use [shellcheck_binary](#shellcheck_binary) to declare the shellcheck target, typically in in `tools/lint/BUILD.bazel`
3. Use [shellcheck_aspect](#shellcheck_aspect) to declare the shellcheck linter aspect, typically in in `tools/lint/linters.bzl`:

```
load("@aspect_rules_lint//lint:shellcheck.bzl", "shellcheck_aspect")

shellcheck = shellcheck_aspect(
    binary = "@@//tools/lint:shellcheck",
    config = "@@//:.shellcheckrc",
)
```


<a id="fetch_shellcheck"></a>

## fetch_shellcheck

<pre>
fetch_shellcheck(<a href="#fetch_shellcheck-version">version</a>)
</pre>

A repository macro used from WORKSPACE to fetch binaries

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="fetch_shellcheck-version"></a>version |  a version of shellcheck that we have mirrored, e.g. <code>v0.9.0</code>   |  <code>"v0.9.0"</code> |


<a id="lint_shellcheck_aspect"></a>

## lint_shellcheck_aspect

<pre>
lint_shellcheck_aspect(<a href="#lint_shellcheck_aspect-binary">binary</a>, <a href="#lint_shellcheck_aspect-config">config</a>)
</pre>

A factory function to create a linter aspect.

Attrs:
    binary: a shellcheck executable.
    config: the .shellcheckrc file

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="lint_shellcheck_aspect-binary"></a>binary |  <p align="center"> - </p>   |  none |
| <a id="lint_shellcheck_aspect-config"></a>config |  <p align="center"> - </p>   |  none |


<a id="shellcheck_action"></a>

## shellcheck_action

<pre>
shellcheck_action(<a href="#shellcheck_action-ctx">ctx</a>, <a href="#shellcheck_action-executable">executable</a>, <a href="#shellcheck_action-srcs">srcs</a>, <a href="#shellcheck_action-config">config</a>, <a href="#shellcheck_action-output">output</a>, <a href="#shellcheck_action-use_exit_code">use_exit_code</a>, <a href="#shellcheck_action-options">options</a>)
</pre>

Run shellcheck as an action under Bazel.

Based on https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="shellcheck_action-ctx"></a>ctx |  Bazel Rule or Aspect evaluation context   |  none |
| <a id="shellcheck_action-executable"></a>executable |  label of the the shellcheck program   |  none |
| <a id="shellcheck_action-srcs"></a>srcs |  bash files to be linted   |  none |
| <a id="shellcheck_action-config"></a>config |  label of the .shellcheckrc file   |  none |
| <a id="shellcheck_action-output"></a>output |  output file to generate   |  none |
| <a id="shellcheck_action-use_exit_code"></a>use_exit_code |  whether to fail the build when a lint violation is reported   |  <code>False</code> |
| <a id="shellcheck_action-options"></a>options |  additional command-line options, see https://github.com/koalaman/shellcheck/blob/master/shellcheck.hs#L95   |  <code>[]</code> |


<a id="shellcheck_binary"></a>

## shellcheck_binary

<pre>
shellcheck_binary(<a href="#shellcheck_binary-name">name</a>)
</pre>

Wrapper around native_binary to select the correct shellcheck executable for the execution platform.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="shellcheck_binary-name"></a>name |  <p align="center"> - </p>   |  none |


