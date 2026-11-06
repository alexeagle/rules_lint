import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

// rules_js replaces process.execPath with a wrapper requiring launcher env.
// Use its underlying Node binary for the fake linter, which has an empty env.
const node = process.env.JS_BINARY__NODE_BINARY || process.execPath;

function runPatcher(t, transform, maxFixPasses, chdir = "") {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "patcher-test-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const execroot = path.join(root, "execroot");
  const sourceRoot = path.join(execroot, chdir);
  fs.mkdirSync(sourceRoot, { recursive: true });
  fs.writeFileSync(path.join(sourceRoot, "source.ts"), "0\n");
  const output = path.join(root, "fix.patch");
  const config = path.join(root, "config.json");
  fs.writeFileSync(
    config,
    JSON.stringify({
      linter: node,
      args: [
        "-e",
        `
      const fs = require('node:fs');
      const value = Number(fs.readFileSync('source.ts', 'utf8'));
      console.log('pass');
      fs.writeFileSync('source.ts', String(${transform}) + '\\n');
    `,
      ],
      env: { BAZEL_BINDIR: chdir || "." },
      ...(chdir ? { chdir } : {}),
      files_to_diff: ["source.ts"],
      output,
      ...(maxFixPasses === undefined ? {} : { max_fix_passes: maxFixPasses }),
    })
  );
  const result = spawnSync(
    node,
    [fileURLToPath(new URL("./patcher.mjs", import.meta.url)), config],
    {
      cwd: execroot,
      env: { ...process.env, JS_BINARY__WORKSPACE: "workspace" },
      encoding: "utf8",
    }
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(
    fs.readFileSync(path.join(sourceRoot, "source.ts"), "utf8"),
    "0\n"
  );
  return {
    patch: fs.readFileSync(output, "utf8"),
    passes: result.stdout.trim().split("\n").length,
    stderr: result.stderr,
  };
}

test("repeats fixes to convergence and leaves original inputs untouched", (t) => {
  const result = runPatcher(t, "Math.min(value + 1, 2)", 10);
  assert.match(result.patch, /\+2\n/);
  assert.equal(result.passes, 3);
  assert.equal(result.stderr, "");
});

test("keeps single-pass behavior for existing callers", (t) => {
  const result = runPatcher(t, "value + 1");
  assert.match(result.patch, /\+1\n/);
  assert.equal(result.passes, 1);
  assert.equal(result.stderr, "");
});

test("stops cyclic fixes before the pass limit", (t) => {
  const result = runPatcher(t, "1 - value", 10);
  assert.equal(result.patch, "");
  assert.equal(result.passes, 2);
  assert.match(result.stderr, /entered a cycle/);
});

test("bounds non-converging fixes and preserves the final patch", (t) => {
  const result = runPatcher(t, "value + 1", 3);
  assert.match(result.patch, /\+3\n/);
  assert.equal(result.passes, 3);
  assert.match(result.stderr, /did not converge after 3 passes/);
});

test("runs native tools from the requested bin directory", (t) => {
  const result = runPatcher(
    t,
    "Math.min(value + 1, 2)",
    10,
    "bazel-out/test/bin"
  );
  assert.match(result.patch, /\+2\n/);
  assert.equal(result.passes, 3);
});
