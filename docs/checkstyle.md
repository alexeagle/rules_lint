<!-- Generated with Stardoc: http://skydoc.bazel.build -->

API for declaring a checkstyle lint aspect that visits java_library rules.

Typical usage:

First, call the `fetch_checkstyle` helper in `WORKSPACE` to download the jar file.
Alternatively you could use whatever you prefer for managing Java dependencies, such as a Maven integration rule.

Next, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
java_binary(
    name = "checkstyle",
    main_class = "com.puppycrawl.tools.checkstyle.Main",
    runtime_deps = ["@com_puppycrawl_tools_checkstyle"],
)
```

Finally, declare an aspect for it, typically in `tools/lint/linters.bzl`:

```starlark
load("@aspect_rules_lint//lint:checkstyle.bzl", "checkstyle_aspect")

checkstyle = checkstyle_aspect(
    binary = "@@//tools/lint:checkstyle",
    config = ["@@//:checkstyle.xml"],
)
```

<a id="checkstyle_action"></a>

## checkstyle_action

<pre>
load("@aspect_rules_lint//lint:checkstyle.bzl", "checkstyle_action")

checkstyle_action(<a href="#checkstyle_action-ctx">ctx</a>, <a href="#checkstyle_action-executable">executable</a>, <a href="#checkstyle_action-srcs">srcs</a>, <a href="#checkstyle_action-config">config</a>, <a href="#checkstyle_action-data">data</a>, <a href="#checkstyle_action-stdout">stdout</a>, <a href="#checkstyle_action-exit_code">exit_code</a>, <a href="#checkstyle_action-options">options</a>)
</pre>

Run Checkstyle as an action under Bazel.

Based on https://checkstyle.sourceforge.io/cmdline.html


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="checkstyle_action-ctx"></a>ctx |  Bazel Rule or Aspect evaluation context   |  none |
| <a id="checkstyle_action-executable"></a>executable |  label of the the Checkstyle program   |  none |
| <a id="checkstyle_action-srcs"></a>srcs |  java files to be linted   |  none |
| <a id="checkstyle_action-config"></a>config |  label of the checkstyle.xml file   |  none |
| <a id="checkstyle_action-data"></a>data |  labels of additional xml files such as suppressions.xml   |  none |
| <a id="checkstyle_action-stdout"></a>stdout |  output file to generate   |  none |
| <a id="checkstyle_action-exit_code"></a>exit_code |  output file to write the exit code. If None, then fail the build when Checkstyle exits non-zero.   |  `None` |
| <a id="checkstyle_action-options"></a>options |  additional command-line options, see https://checkstyle.sourceforge.io/cmdline.html   |  `[]` |


<a id="fetch_checkstyle"></a>

## fetch_checkstyle

<pre>
load("@aspect_rules_lint//lint:checkstyle.bzl", "fetch_checkstyle")

fetch_checkstyle()
</pre>





<a id="lint_checkstyle_aspect"></a>

## lint_checkstyle_aspect

<pre>
load("@aspect_rules_lint//lint:checkstyle.bzl", "lint_checkstyle_aspect")

lint_checkstyle_aspect(<a href="#lint_checkstyle_aspect-binary">binary</a>, <a href="#lint_checkstyle_aspect-config">config</a>, <a href="#lint_checkstyle_aspect-configs">configs</a>, <a href="#lint_checkstyle_aspect-data">data</a>, <a href="#lint_checkstyle_aspect-rule_kinds">rule_kinds</a>)
</pre>

A factory function to create a linter aspect.

Attrs:
    binary: a Checkstyle executable. Can be obtained from rules_java like so:

        ```
        java_binary(
            name = "checkstyle",
            main_class = "com.puppycrawl.tools.checkstyle.Main",
            # Point to wherever you have the java_import rule defined, see our example
            runtime_deps = ["@com_puppycrawl_tools_checkstyle"],
        )
        ```

    config: the Checkstyle XML file

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="lint_checkstyle_aspect-binary"></a>binary |  <p align="center"> - </p>   |  none |
| <a id="lint_checkstyle_aspect-config"></a>config |  <p align="center"> - </p>   |  none |
| <a id="lint_checkstyle_aspect-configs"></a>configs |  <p align="center"> - </p>   |  `{}` |
| <a id="lint_checkstyle_aspect-data"></a>data |  <p align="center"> - </p>   |  `[]` |
| <a id="lint_checkstyle_aspect-rule_kinds"></a>rule_kinds |  <p align="center"> - </p>   |  `["java_binary", "java_library"]` |


<a id="rebuild_map"></a>

## rebuild_map

<pre>
load("@aspect_rules_lint//lint:checkstyle.bzl", "rebuild_map")

rebuild_map(<a href="#rebuild_map-configs">configs</a>)
</pre>



**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="rebuild_map-configs"></a>configs |  <p align="center"> - </p>   |  none |


