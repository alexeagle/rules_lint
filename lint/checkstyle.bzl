"""API for declaring a checkstyle lint aspect that visits java_library rules.

Typical usage:

First, call the tools.checkstyle module extension to download the jar file.
Alternatively you could use whatever you prefer for managing Java dependencies, such as a Maven integration rule.

Next, declare a binary target for it, typically in `tools/lint/BUILD.bazel`:

```starlark
java_binary(
    name = "checkstyle",
    main_class = "com.puppycrawl.tools.checkstyle.Main",
    runtime_deps = ["@com_puppycrawl_tools_checkstyle//jar"],
)
```

Finally, declare an aspect for it, typically in `tools/lint/linters.bzl`:

```starlark
load("@rules_lint//lint:checkstyle.bzl", "lint_checkstyle_aspect")

checkstyle = lint_checkstyle_aspect(
    binary = Label("//tools/lint:checkstyle"),
    config = Label("//:checkstyle.xml"),
)
```
"""

load("//lint/private:lint_aspect.bzl", "LintOptionsInfo", "filter_srcs", "noop_lint_action", "output_files", "should_visit")

_MNEMONIC = "AspectRulesLintCheckstyle"

def checkstyle_action(ctx, executable, srcs, config, data, stdout, exit_code = None, args = []):
    """Run Checkstyle as an action under Bazel.

    Based on https://checkstyle.sourceforge.io/cmdline.html

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: label of the Checkstyle program
        srcs: java files to be linted
        config: label of the checkstyle.xml file
        data: labels of additional xml files such as suppressions.xml
        stdout: output file to generate
        exit_code: output file to write the exit code.
            If None, then fail the build when Checkstyle exits non-zero.
        args: additional command-line options, see https://checkstyle.sourceforge.io/cmdline.html
    """
    inputs = srcs + [config] + data
    outputs = [stdout]

    # Wire command-line options, see
    # https://checkstyle.sourceforge.io/cmdline.html
    action_args = ctx.actions.args()
    action_args.add_all(args)

    action_args.add_all(["-c", config.path])
    action_args.add_all(srcs)

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
        arguments = [action_args],
        mnemonic = _MNEMONIC,
        tools = [executable],
        progress_message = "Linting %{label} with Checkstyle",
    )

# buildifier: disable=function-docstring
def _checkstyle_aspect_impl(target, ctx):
    if not should_visit(ctx.rule, ctx.attr._rule_kinds):
        return []

    files_to_lint = filter_srcs(ctx.rule)
    outputs, info = output_files(_MNEMONIC, target, ctx)
    if len(files_to_lint) == 0:
        noop_lint_action(ctx, outputs)
        return [info]

    checkstyle_action(
        ctx,
        ctx.executable._checkstyle,
        files_to_lint,
        ctx.file._config,
        ctx.files._data,
        outputs.human.out,
        outputs.human.exit_code,
        ctx.attr._args + ["-f", "plain"],
    )
    checkstyle_action(
        ctx,
        ctx.executable._checkstyle,
        files_to_lint,
        ctx.file._config,
        ctx.files._data,
        outputs.machine.out,
        outputs.machine.exit_code,
        ctx.attr._args + ["-f", "sarif"],
    )
    return [info]

def lint_checkstyle_aspect(binary, config, data = [], rule_kinds = ["java_binary", "java_library"], args = []):
    """A factory function to create a linter aspect.

    Attrs:
        binary: a Checkstyle executable. Obtain from rules_java like so:

            java_binary(
                name = "checkstyle",
                main_class = "com.puppycrawl.tools.checkstyle.Main",
                # Point to wherever you have the java_import rule defined, see our example
                runtime_deps = ["@com_puppycrawl_tools_checkstyle"],
            )

        config: the Checkstyle XML file
        args: Additional options to pass to Checkstyle
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
            "_data": attr.label_list(
                doc = "Additional files to make available to Checkstyle such as any included XML files",
                allow_files = True,
                default = data,
            ),
            "_rule_kinds": attr.string_list(
                default = rule_kinds,
            ),
            "_args": attr.string_list(
                default = args,
            ),
        },
    )
