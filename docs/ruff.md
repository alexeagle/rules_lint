<!-- Generated with Stardoc: http://skydoc.bazel.build -->

API for declaring a Ruff lint aspect that visits py_library rules.

Typical usage:

```
load("@aspect_rules_lint//lint:ruff.bzl", "ruff_aspect")

ruff = ruff_aspect(
    binary = "@@//:ruff",
    configs = "@@//:.ruff.toml",
)
```


<a id="ruff_workaround_20269"></a>

## ruff_workaround_20269

<pre>
ruff_workaround_20269(<a href="#ruff_workaround_20269-name">name</a>, <a href="#ruff_workaround_20269-build_file_content">build_file_content</a>, <a href="#ruff_workaround_20269-repo_mapping">repo_mapping</a>, <a href="#ruff_workaround_20269-sha256">sha256</a>, <a href="#ruff_workaround_20269-url">url</a>)
</pre>

Workaround for https://github.com/bazelbuild/bazel/issues/20269

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="ruff_workaround_20269-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="ruff_workaround_20269-build_file_content"></a>build_file_content |  -   | String | optional | <code>""</code> |
| <a id="ruff_workaround_20269-repo_mapping"></a>repo_mapping |  A dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.&lt;p&gt;For example, an entry <code>"@foo": "@bar"</code> declares that, for any time this repository depends on <code>@foo</code> (such as a dependency on <code>@foo//some:target</code>, it should actually resolve that dependency within globally-declared <code>@bar</code> (<code>@bar//some:target</code>).   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | required |  |
| <a id="ruff_workaround_20269-sha256"></a>sha256 |  -   | String | optional | <code>""</code> |
| <a id="ruff_workaround_20269-url"></a>url |  -   | String | optional | <code>""</code> |


<a id="fetch_ruff"></a>

## fetch_ruff

<pre>
fetch_ruff(<a href="#fetch_ruff-version">version</a>)
</pre>

A repository macro used from WORKSPACE to fetch ruff binaries

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="fetch_ruff-version"></a>version |  a version of ruff that we have mirrored, e.g. <code>v0.1.0</code>   |  <code>"v0.1.8"</code> |


<a id="ruff_action"></a>

## ruff_action

<pre>
ruff_action(<a href="#ruff_action-ctx">ctx</a>, <a href="#ruff_action-executable">executable</a>, <a href="#ruff_action-srcs">srcs</a>, <a href="#ruff_action-config">config</a>, <a href="#ruff_action-report">report</a>, <a href="#ruff_action-use_exit_code">use_exit_code</a>)
</pre>

Run ruff as an action under Bazel.

Ruff will select the configuration file to use for each source file, as documented here:
https://docs.astral.sh/ruff/configuration/#config-file-discovery

Note: all config files are passed to the action.
This means that a change to any config file invalidates the action cache entries for ALL
ruff actions.

However this is needed because:

1. ruff has an `extend` field, so it may need to read more than one config file
2. ruff's logic for selecting the appropriate config needs to read the file content to detect
  a `[tool.ruff]` section.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="ruff_action-ctx"></a>ctx |  Bazel Rule or Aspect evaluation context   |  none |
| <a id="ruff_action-executable"></a>executable |  label of the the ruff program   |  none |
| <a id="ruff_action-srcs"></a>srcs |  python files to be linted   |  none |
| <a id="ruff_action-config"></a>config |  labels of ruff config files (pyproject.toml, ruff.toml, or .ruff.toml)   |  none |
| <a id="ruff_action-report"></a>report |  output file to generate   |  none |
| <a id="ruff_action-use_exit_code"></a>use_exit_code |  whether to fail the build when a lint violation is reported   |  <code>False</code> |


<a id="ruff_aspect"></a>

## ruff_aspect

<pre>
ruff_aspect(<a href="#ruff_aspect-binary">binary</a>, <a href="#ruff_aspect-configs">configs</a>)
</pre>

A factory function to create a linter aspect.

Attrs:
    binary: a ruff executable. Can be obtained like so:

        load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

        http_archive(
            name = "ruff_bin_linux_amd64",
            sha256 = "&lt;-sha-&gt;",
            urls = [
                "https://github.com/charliermarsh/ruff/releases/download/v&lt;-version-&gt;/ruff-x86_64-unknown-linux-gnu.tar.gz",
            ],
            build_file_content = """exports_files(["ruff"])""",
        )

    configs: ruff config file(s) (`pyproject.toml`, `ruff.toml`, or `.ruff.toml`)

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="ruff_aspect-binary"></a>binary |  <p align="center"> - </p>   |  none |
| <a id="ruff_aspect-configs"></a>configs |  <p align="center"> - </p>   |  none |


