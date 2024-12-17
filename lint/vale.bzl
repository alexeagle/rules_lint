"""API for declaring a Vale lint aspect that visits markdown files.

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
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "output_files", "should_visit")
load(":vale_library.bzl", "fetch_styles")
load(":vale_versions.bzl", "VALE_VERSIONS")

_MNEMONIC = "AspectRulesLintVale"

def vale_action(ctx, executable, srcs, styles, config, stdout, exit_code = None, output = "CLI", env = {}):
    """Run Vale as an action under Bazel.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the the Vale program
        srcs: markdown files to be linted
        styles: a directory containing vale extensions, following https://vale.sh/docs/topics/styles/
        config: label of the .vale.ini file, see https://vale.sh/docs/vale-cli/structure/#valeini
        stdout: output file containing stdout of Vale
        exit_code: output file containing Vale exit code.
            If None, then fail the build when Vale exits non-zero.
        output: the value for the --output flag
        env: environment variables for vale
    """
    inputs = srcs + [config]

    if styles:
        inputs.append(styles)

        # Introduced in https://github.com/errata-ai/vale/commit/2139c4176a4d2e62d7dfb95dca24b96b9e8b7251
        # and released in v3.1.0
        env = dict(env, **{"VALE_STYLES_PATH": styles.path})

    # Wire command-line options, see output of vale --help
    args = ctx.actions.args()
    args.add_all(srcs)
    args.add_all(["--config", config])
    args.add_all(["--output", output])
    outputs = [stdout]

    if exit_code:
        command = "{vale} $@ >{stdout}; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        # Create empty file on success, as Bazel expects one
        command = "{vale} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        command = command.format(
            vale = executable.path,
            stdout = stdout.path,
        ),
        env = env,
        arguments = [args],
        mnemonic = _MNEMONIC,
        progress_message = "Linting %{label} with Vale",
        tools = [executable],
    )

# buildifier: disable=function-docstring
def _vale_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds, ctx.attr._filegroup_tags):
        return []

    # The "CLI" output style is automatically colored unless disabled
    color_env = {} if ctx.attr._options[LintOptionsInfo].color else {"NO_COLOR": "1"}
    outputs, info = output_files(_MNEMONIC, target, ctx)
    styles = None
    if ctx.files._styles:
        if len(ctx.files._styles) != 1:
            fail("Only a single directory should be in styles")
        styles = ctx.files._styles[0]
        if not styles.is_directory:
            fail("Styles should be a directory containing installed styles")
    vale_action(ctx, ctx.executable._vale, ctx.rule.files.srcs, styles, ctx.file._config, outputs.human.out, outputs.human.exit_code, env = color_env)
    vale_action(ctx, ctx.executable._vale, ctx.rule.files.srcs, styles, ctx.file._config, outputs.machine.out, outputs.machine.exit_code, output = "line")
    return [info]

# There's no "official" markdown_library rule.
# Users might want to try https://github.com/dwtj/dwtj_rules_markdown but we expect many won't
# want to take that dependency.
# So allow a filegroup(tags=["markdown"]) as an alternative rule to host the srcs.
def lint_vale_aspect(binary, config, styles = Label("//lint:empty_styles"), rule_kinds = ["markdown_library"], filegroup_tags = ["markdown", "lint-with-vale"]):
    """A factory function to create a linter aspect."""
    return aspect(
        implementation = _vale_aspect_impl,
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_vale": attr.label(
                default = binary,
                executable = True,
                cfg = "exec",
            ),
            "_config": attr.label(
                allow_single_file = True,
                mandatory = True,
                doc = "Config file",
                default = config,
            ),
            "_styles": attr.label(
                default = styles,
            ),
            "_filegroup_tags": attr.string_list(
                default = filegroup_tags,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
        },
    )

def fetch_vale(tag = VALE_VERSIONS.keys()[0]):
    """A repository macro used from WORKSPACE to fetch vale binaries

    Args:
        tag: a tag of vale that we have mirrored, e.g. `v3.0.5`
    """
    version = tag.lstrip("v")
    url = "https://github.com/errata-ai/vale/releases/download/{tag}/vale_{version}_{plat}.{ext}"

    for plat, sha256 in VALE_VERSIONS[tag].items():
        is_windows = plat.startswith("Windows")

        maybe(
            http_archive,
            name = "vale_" + plat,
            url = url.format(
                tag = tag,
                plat = plat,
                version = version,
                ext = "zip" if is_windows else "tar.gz",
            ),
            sha256 = sha256,
            build_file_content = """exports_files(["vale", "vale.exe"])""",
        )

    fetch_styles()

def _vale_dependencies_impl(_ctx):
    fetch_vale()

vale_dependencies = module_extension(
    implementation = _vale_dependencies_impl,
)
