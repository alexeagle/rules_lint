<!-- Generated with Stardoc: http://skydoc.bazel.build -->

API for declaring a Vale lint aspect that visits markdown files.

First, all markdown sources must be the srcs of some Bazel rule.
Either use a `filegroup` with `markdown` in the `tags`:

```python
filegroup(
    name = "md",
    srcs = glob(["*.md"]),
    tags = ["markdown"],
)
```

or use a `markdown_library` rule such as the one in <https://github.com/dwtj/dwtj_rules_markdown>.
Aspect plans to provide support for Markdown in [configure]() so these rules can be automatically
maintained rather than requiring developers to write them by hand.

Note that any Markdown files in the repo which aren't in the `srcs` of one of these rules will *not*
be linted by Vale.

## Styles

Vale is powered by [Styles](https://vale.sh/docs/vale-cli/structure/#styles).
There is a [built-in style](https://vale.sh/docs/topics/styles/#built-in-style) and if this is
sufficient then it's not necessary to follow the rest of this section.

The styles from https://vale.sh/hub/ are already fetched by `fetch_vale()` which has a Bazel-based
mirror of https://github.com/errata-ai/packages/blob/master/library.json.
It's possible to fetch more styles using a typical `http_archive()` call.

At runtime, Vale requires the styles are "installed" into a folder together.
Use the [`copy_to_directory`](https://docs.aspect.build/rulesets/aspect_bazel_lib/docs/copy_to_directory/)
rule to accomplish this, for example,

```python
copy_to_directory(
    name = "vale_styles",
    srcs = ["@vale_write-good//:write-good"],
    include_external_repositories = ["vale_*"],
)
```

Note that the `.vale.ini` file may have a `StylesPath` entry.
Under Bazel, we set `VALE_STYLES_PATH` in the environment, so the `StylesPath` is used
only when running Vale outside Bazel, such as in an editor extension.

See the example in rules_lint for a fully-working vale setup.

## Usage

```starlark
load("@aspect_rules_lint//lint:vale.bzl", "vale_aspect")

vale = vale_aspect(
    binary = "@@//tools/lint:vale",
    # A copy_to_bin rule that places the .vale.ini file into bazel-bin
    config = "@@//:.vale_ini",
    # Optional.
    # A copy_to_directory rule that "installs" custom styles together into a single folder
    styles = "@@//tools/lint:vale_styles",
)
```

<a id="fetch_vale"></a>

## fetch_vale

<pre>
load("@aspect_rules_lint//lint:vale.bzl", "fetch_vale")

fetch_vale(<a href="#fetch_vale-tag">tag</a>)
</pre>

A repository macro used from WORKSPACE to fetch vale binaries

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="fetch_vale-tag"></a>tag |  a tag of vale that we have mirrored, e.g. `v3.0.5`   |  `"v3.7.0"` |


<a id="lint_vale_aspect"></a>

## lint_vale_aspect

<pre>
load("@aspect_rules_lint//lint:vale.bzl", "lint_vale_aspect")

lint_vale_aspect(<a href="#lint_vale_aspect-binary">binary</a>, <a href="#lint_vale_aspect-config">config</a>, <a href="#lint_vale_aspect-styles">styles</a>, <a href="#lint_vale_aspect-rule_kinds">rule_kinds</a>, <a href="#lint_vale_aspect-filegroup_tags">filegroup_tags</a>)
</pre>

A factory function to create a linter aspect.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="lint_vale_aspect-binary"></a>binary |  <p align="center"> - </p>   |  none |
| <a id="lint_vale_aspect-config"></a>config |  <p align="center"> - </p>   |  none |
| <a id="lint_vale_aspect-styles"></a>styles |  <p align="center"> - </p>   |  `Label("@aspect_rules_lint//lint:empty_styles")` |
| <a id="lint_vale_aspect-rule_kinds"></a>rule_kinds |  <p align="center"> - </p>   |  `["markdown_library"]` |
| <a id="lint_vale_aspect-filegroup_tags"></a>filegroup_tags |  <p align="center"> - </p>   |  `["markdown", "lint-with-vale"]` |


<a id="vale_action"></a>

## vale_action

<pre>
load("@aspect_rules_lint//lint:vale.bzl", "vale_action")

vale_action(<a href="#vale_action-ctx">ctx</a>, <a href="#vale_action-executable">executable</a>, <a href="#vale_action-srcs">srcs</a>, <a href="#vale_action-styles">styles</a>, <a href="#vale_action-config">config</a>, <a href="#vale_action-stdout">stdout</a>, <a href="#vale_action-exit_code">exit_code</a>, <a href="#vale_action-output">output</a>, <a href="#vale_action-env">env</a>)
</pre>

Run Vale as an action under Bazel.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="vale_action-ctx"></a>ctx |  Bazel Rule or Aspect evaluation context   |  none |
| <a id="vale_action-executable"></a>executable |  label of the the Vale program   |  none |
| <a id="vale_action-srcs"></a>srcs |  markdown files to be linted   |  none |
| <a id="vale_action-styles"></a>styles |  a directory containing vale extensions, following https://vale.sh/docs/topics/styles/   |  none |
| <a id="vale_action-config"></a>config |  label of the .vale.ini file, see https://vale.sh/docs/vale-cli/structure/#valeini   |  none |
| <a id="vale_action-stdout"></a>stdout |  output file containing stdout of Vale   |  none |
| <a id="vale_action-exit_code"></a>exit_code |  output file containing Vale exit code. If None, then fail the build when Vale exits non-zero.   |  `None` |
| <a id="vale_action-output"></a>output |  the value for the --output flag   |  `"CLI"` |
| <a id="vale_action-env"></a>env |  environment variables for vale   |  `{}` |


<a id="vale_dependencies"></a>

## vale_dependencies

<pre>
vale_dependencies = use_extension("@aspect_rules_lint//lint:vale.bzl", "vale_dependencies")
</pre>



