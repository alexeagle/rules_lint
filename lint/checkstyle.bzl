"""API for declaring a checkstyle lint aspect that visits java_library rules.

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
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_jar")
load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "filter_srcs", "noop_lint_action", "output_files", "should_visit")

_MNEMONIC = "AspectRulesLintCheckstyle"

def rebuild_map(configs):
    directory_to_config = {}
    for config, directories in configs.items():
        for directory in directories.split(","):
            directory_to_config[directory] = config
    return directory_to_config

def checkstyle_action(ctx, executable, srcs, config, data, stdout, exit_code = None, options = []):
    """Run Checkstyle as an action under Bazel.

    Based on https://checkstyle.sourceforge.io/cmdline.html

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the the Checkstyle program
        srcs: java files to be linted
        config: label of the checkstyle.xml file
        configs: dictionary mapping package label to their respective checkstyle.xml file
        data: labels of additional xml files such as suppressions.xml
        stdout: output file to generate
        exit_code: output file to write the exit code.
            If None, then fail the build when Checkstyle exits non-zero.
        options: additional command-line options, see https://checkstyle.sourceforge.io/cmdline.html
    """
    inputs = srcs + [config] + data
    outputs = [stdout]

    # Wire command-line options, see
    # https://checkstyle.sourceforge.io/cmdline.html
    args = ctx.actions.args()
    args.add_all(options)

    args.add_all(["-c", config.path])
    args.add_all(srcs)

    if exit_code:
        command = "{CHECKSTYLE} $@ >{stdout}; echo $? > " + exit_code.path
        outputs.append(exit_code)
    else:
        # Create empty stdout file on success, as Bazel expects one
        command = "{CHECKSTYLE} $@ && touch {stdout}"

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = outputs,
        command = command.format(CHECKSTYLE = executable.path, stdout = stdout.path),
        arguments = [args],
        mnemonic = _MNEMONIC,
        tools = [executable],
        progress_message = "Linting %{label} with Checkstyle",
    )

# buildifier: disable=function-docstring
def _checkstyle_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    files_to_lint = filter_srcs(ctx.rule)
    config_file = ctx.file._config
    config_maps = rebuild_map(ctx.attr._configs)
    if ctx.attr._configs:
        label = str(target.label)
        keys = sorted(config_maps.keys(), key=len, reverse = True)
        for key in keys:
            if label.startswith(key):
                config = config_maps[key]
                config_file = config.files.to_list()[0]
                break

    outputs, info = output_files(_MNEMONIC, target, ctx)
    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    checkstyle_action(
        ctx,
        ctx.executable._checkstyle,
        files_to_lint,
        config_file,
        ctx.files._data,
        outputs.human.out,
        outputs.human.exit_code,
        ["-f", "plain"],
    )
    checkstyle_action(
        ctx,
        ctx.executable._checkstyle,
        files_to_lint,
        config_file,
        ctx.files._data,
        outputs.machine.out,
        outputs.machine.exit_code,
        ["-f", "sarif"],
    )
    return [info]

def lint_checkstyle_aspect(binary, config, configs = {}, data = [], rule_kinds = ["java_binary", "java_library"]):
    """A factory function to create a linter aspect.

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
    """
    return aspect(
        implementation = _checkstyle_aspect_impl,
        # Edges we need to walk up the graph from the selected targets.
        # Needed for linters that need semantic information like transitive type declarations.
        # attr_aspects = ["deps"],
        attrs = {
            "_options": attr.label(
                default = "//lint:options",
                providers = [LintOptionsInfo],
            ),
            "_checkstyle": attr.label(
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
            "_configs": attr.label_keyed_string_dict(
                allow_empty = True,
                allow_files = True,
                doc = "Package and configuration files dictionary",
                default = configs,
            ),
            "_data": attr.label_list(
                doc = "Additional files to make available to Checkstyle such as any included XML files",
                allow_files = True,
                default = data,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
        },
    )

def fetch_checkstyle():
    http_jar(
        name = "com_puppycrawl_tools_checkstyle",
        url = "https://github.com/checkstyle/checkstyle/releases/download/checkstyle-10.17.0/checkstyle-10.17.0-all.jar",
        sha256 = "51c34d738520c1389d71998a9ab0e6dabe0d7cf262149f3e01a7294496062e42",
    )
