"Shared starlark helpers for executing the patcher.mjs script"
patcher_attrs = {
    "_patcher": attr.label(
        default = "@rules_lint//lint/private:patcher",
        executable = True,
        cfg = "exec",
    ),
}

def run_patcher(
        ctx,
        executable,
        inputs,
        args,
        files_to_diff,
        patch_out,
        tools,
        stdout = None,
        stderr = None,
        exit_code = None,
        patch_cfg_env = None,
        env = None,
        mnemonic = None,
        progress_message = None,
        patch_cfg_suffix = "patch_cfg",
        patch_cfg_name = None):
    """Run the linter in a sandbox, in a mode where it applies fixes to source files it reads.

    Collects the edits made to the sandbox into a patch file.

    Args:
        ctx: Bazel Rule or Aspect evaluation context
        executable: struct with a _patcher field
        inputs: action inputs (list or depset)
        args: Args object or list of arguments to pass to the linter
        files_to_diff: list of file paths to diff
        patch_out: output file for the patch
        tools: tools for the action (first tool is used as the linter)
        stdout: output file for stdout (optional)
        stderr: output file for stderr (optional)
        exit_code: output file for exit code (optional)
        patch_cfg_env: environment variables for the patch config (optional)
        env: additional environment variables for the action (will be merged with common env vars)
        mnemonic: action mnemonic
        progress_message: action progress message
        patch_cfg_suffix: suffix for the patch config file name (default: "patch_cfg")
        patch_cfg_name: patch config file name minus the suffix (default: ctx.label.name)
    """

    # Create a patch config file to pass arguments to the patcher.mjs script
    if patch_cfg_name == None:
        patch_cfg_name = ctx.label.name
    patch_cfg = ctx.actions.declare_file("_{}.{}".format(patch_cfg_name, patch_cfg_suffix))
    arguments = [patch_cfg.path]

    # Build patch config dictionary
    patch_cfg_dict = {
        "linter": tools[0].path,  # Derive linter path from the first tool
        "files_to_diff": files_to_diff,
        "output": patch_out.path,
    }
    if patch_cfg_env != None:
        patch_cfg_dict["env"] = patch_cfg_env

    if type(args) == "Args":
        args.use_param_file("%s", use_always=True)
        args.set_param_file_format("multiline")
        arguments.append(args)
    else:
        patch_cfg_dict["args"] = args

    ctx.actions.write(
        output = patch_cfg,
        content = json.encode(patch_cfg_dict),
    )

    # Build common environment variables and outputs list
    common_env = {
        "BAZEL_BINDIR": ".",
        "JS_BINARY__SILENT_ON_SUCCESS": "1",
    }

    outputs_list = [patch_out]
    if stdout != None:
        common_env["JS_BINARY__STDOUT_OUTPUT_FILE"] = stdout.path
        outputs_list.append(stdout)
    if stderr != None:
        common_env["JS_BINARY__STDERR_OUTPUT_FILE"] = stderr.path
        outputs_list.append(stderr)
    if exit_code != None:
        common_env["JS_BINARY__EXIT_CODE_OUTPUT_FILE"] = exit_code.path
        outputs_list.append(exit_code)

    # Merge with provided env if any
    if env != None:
        final_env = env | common_env
    else:
        final_env = common_env

    # Add patch_cfg to inputs if it's a list, otherwise it should be in a depset
    if type(inputs) == "list":
        final_inputs = inputs + [patch_cfg]
    elif type(inputs) == "depset":
        # For depset, we need to create a new depset that includes patch_cfg
        final_inputs = depset([patch_cfg], transitive = [inputs])
    else:
        fail("inputs must be a list or depset, got {}".format(type(inputs)))

    kwargs = {
        "inputs": final_inputs,
        "outputs": outputs_list,
        "executable": executable._patcher,
        "arguments": arguments,
        "env": final_env,
        "tools": tools,
    }
    if mnemonic != None:
        kwargs["mnemonic"] = mnemonic
    if progress_message != None:
        kwargs["progress_message"] = progress_message
    ctx.actions.run(**kwargs)
