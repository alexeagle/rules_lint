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

or use a `markdown_library` rule such as the one in [dwtj_rules_markdown](https://github.com/dwtj/dwtj_rules_markdown).
Aspect plans to provide support for Markdown in [configure]() so these rules can be automatically
maintained rather than requiring developers to write them by hand.

Note that any Markdown files in the repo which aren't in the `srcs` of one of these rules will *not*
be linted by Vale.

## Styles

Vale is powered by [Styles](https://vale.sh/docs/vale-cli/structure/#styles).
There is a [built-in style](https://vale.sh/docs/topics/styles/#built-in-style) and if this is
sufficient then it's not necessary to follow the rest of this section.

The styles from https://vale.sh/hub/ are already fetched by tools.vale_styles module extension which has a Bazel-based
mirror of https://github.com/errata-ai/packages/blob/master/library.json.
It's possible to fetch more styles using a typical `http_archive()` call.

At runtime, Vale requires the styles are "installed" into a folder together.
Use the [`copy_to_directory`](https://docs.aspect.build/rulesets/bazel_lib/docs/copy_to_directory/)
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
load("@rules_lint//lint:vale.bzl", "lint_vale_aspect")

vale = lint_vale_aspect(
    binary = Label("//tools/lint:vale"),
    # A copy_to_bin rule that places the .vale.ini file into bazel-bin
    config = Label("//:.vale_ini"),
    # Optional.
    # A copy_to_directory rule that "installs" custom styles together into a single folder
    styles = Label("//tools/lint:vale_styles"),
)
```
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "OPTIONAL_SARIF_PARSER_TOOLCHAIN", "OUTFILE_FORMAT", "output_files", "parse_to_sarif_action", "should_visit")

_MNEMONIC = "AspectRulesLintVale"

def vale_action(ctx, executable, srcs, styles, config, stdout, exit_code = None, output = "CLI", env = {}, args = []):
    """Run Vale as an action under Bazel.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the Vale program
        srcs: markdown files to be linted
        styles: a directory containing vale extensions, following https://vale.sh/docs/topics/styles/
        config: label of the .vale.ini file, see https://vale.sh/docs/vale-cli/structure/#valeini
        stdout: output file containing stdout of Vale
        exit_code: output file containing Vale exit code.
            If None, then fail the build when Vale exits non-zero.
        output: the value for the --output flag. May be a string like 'line', 'JSON', 'CLI', or a File of a template to use: https://vale.sh/docs/templates
        env: environment variables for vale
        args: additional command-line arguments passed to Vale
    """
    inputs = srcs + [config]

    if styles:
        inputs.append(styles)

        # Introduced in https://github.com/errata-ai/vale/commit/2139c4176a4d2e62d7dfb95dca24b96b9e8b7251
        # and released in v3.1.0
        env = dict(env, **{"VALE_STYLES_PATH": styles.path})

    # Wire command-line options, see output of vale --help
    action_args = ctx.actions.args()
    action_args.add_all(args)
    action_args.add_all(srcs)
    action_args.add_all(["--config", config])
    if type(output) == "File":
        inputs.append(output)
        action_args.add_all(["--output", output.path])
    else:
        action_args.add_all(["--output", output])
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
        arguments = [action_args],
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
    output = ctx.file._template if hasattr(ctx.attr, "_template") and ctx.files._template else "CLI"
    vale_action(ctx, ctx.executable._vale, ctx.rule.files.srcs, styles, ctx.file._config, outputs.human.out, outputs.human.exit_code, env = color_env, output = output, args = ctx.attr._args)
    raw_machine_report = ctx.actions.declare_file(OUTFILE_FORMAT.format(label = target.label.name, mnemonic = _MNEMONIC, suffix = "raw_machine_report"))
    vale_action(ctx, ctx.executable._vale, ctx.rule.files.srcs, styles, ctx.file._config, raw_machine_report, outputs.machine.exit_code, output = "line", args = ctx.attr._args)
    parse_to_sarif_action(ctx, _MNEMONIC, raw_machine_report, outputs.machine.out)
    return [info]

# There's no "official" markdown_library rule.
# Users might want to try https://github.com/dwtj/dwtj_rules_markdown but we expect many won't
# want to take that dependency.
# So allow a filegroup(tags=["markdown"]) as an alternative rule to host the srcs.
def lint_vale_aspect(binary, config, template = None, styles = Label("//lint:empty_styles"), rule_kinds = ["markdown_library"], filegroup_tags = ["markdown", "lint-with-vale"], args = []):
    """A factory function to create a linter aspect.

    Args:
        binary: a Vale executable, typically fetched by the `tools.vale()` module extension.
        config: the label of the `.vale.ini` file used by Vale.
        template: an optional label of a `.tmpl` file passed to `vale --output`.
        styles: a label of a directory containing installed Vale styles.
        rule_kinds: which [kinds](https://bazel.build/query/language#kind) of rules should be visited by the aspect.
        filegroup_tags: filegroups tagged with these tags will also be visited by the aspect.
        args: additional options to pass to Vale.

    Returns:
        An aspect definition for Vale.
    """
    extra_attrs = {}
    if template:
        extra_attrs["_template"] = attr.label(
            allow_single_file = [".tmpl"],
            default = template,
        )
    return aspect(
        implementation = _vale_aspect_impl,
        attrs = dicts.add(
            {
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
                "_args": attr.string_list(
                    default = args,
                ),
            },
            extra_attrs,
        ),
        toolchains = [OPTIONAL_SARIF_PARSER_TOOLCHAIN],
    )
