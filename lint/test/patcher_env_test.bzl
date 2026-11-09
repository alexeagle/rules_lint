"Analysis test: the patcher action gets PATH from --action_env, which its js_binary launcher needs"

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

_PATH = "/patcher_env_test/bin"

def _patcher_env_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "Patcher"]
    asserts.equals(env, 1, len(actions))
    asserts.equals(env, _PATH, actions[0].env.get("PATH"))
    return analysistest.end(env)

patcher_env_test = analysistest.make(
    _patcher_env_test_impl,
    config_settings = {"//command_line_option:action_env": ["PATH=" + _PATH]},
)
