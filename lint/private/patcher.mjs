/**
 * @fileoverview wrapper around linter tools to create a writeable sandbox of source files,
 * then collect the resulting modifications as a patch file.
 *
 * The design philosophy is that the linters should be run exactly the same way as they were to
 * produce the report of violations. This program should work with any linter tool, using any
 * language runtime.
 */
import childProcess from "node:child_process";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";
import crypto from "node:crypto";

function debug(...kwargs) {
  if (!!process.env.JS_BINARY__LOG_DEBUG) {
    console.error(...kwargs);
  }
}

// assumes there are no recursive symlinks
async function sync(src, dst, subdir, filesToDiff) {
  const files = (await fs.promises.readdir(path.join(src, subdir))).map((f) =>
    path.join(subdir, f)
  );
  for (const f of files) {
    const srcF = path.join(src, f);
    const dstF = path.join(dst, f);
    if (filesToDiff.includes(f)) {
      debug(`copying ${f}`);
      await fs.promises.mkdir(path.dirname(dstF), { recursive: true });
      // NB: `fs.promises.copyFile` dates back to Node.js 10 (https://nodejs.org/api/fs.html#fspromisescopyfilesrc-dest-mode)
      // while `fs.promises.cp` is only added in Node.js 16.7 (https://nodejs.org/api/fs.html#fspromisescpsrc-dest-options) and
      // still tagged as experimental so we should use `copyFile` here. `copyFile` will also de-reference a src symlink by default
      // while with `cp` the `deference` option must be set explicitly.
      await fs.promises.copyFile(srcF, dstF);
      await fs.promises.chmod(dstF, "600");
    } else if (
      filesToDiff.find((d) => d.startsWith(f + path.sep)) !== undefined
    ) {
      debug(`entering ${f}`);
      await sync(src, dst, f, filesToDiff);
    } else {
      debug(`symlinking ${f}`);
      await fs.promises.mkdir(path.dirname(dstF), { recursive: true });
      await fs.promises.symlink(srcF, dstF);
    }
  }
}

async function main(args, sandbox) {
  const config = JSON.parse(await fs.promises.readFile(args[0]));
  const spawnArgs =
    args.length > 1
      ? (await fs.promises.readFile(args[1], "utf8"))
          .split(/\r?\n/)
          .filter(Boolean)
      : config.args;

  debug("sandbox", sandbox);
  debug("config", JSON.stringify(config, null, 2));
  // JS-specific workaround where sources are copied-to-bin
  const sourcePrefix = config.env?.BAZEL_BINDIR || ".";

  // sync the execroot to a custom sandbox; files_to_diff are copied
  // and all other files in the execroot are symlinked at their lowest
  // point that is not a root of any files_to_diff.
  debug(`syncing ${process.cwd()} to ${sandbox}`);
  await sync(
    process.cwd(),
    sandbox,
    ".",
    config.files_to_diff.map((f) => path.join(sourcePrefix, f))
  );

  debug(
    `spawning linter: ${config.linter} ${spawnArgs.join(
      " "
    )} (with env ${JSON.stringify(config.env || {})})`
  );
  const maxFixPasses = config.max_fix_passes || 1;
  // Oxlint applies one set of non-overlapping fixes per invocation. Hash only
  // writable sources so another pass can finish fixes exposed by the previous
  // one. See https://github.com/oxc-project/oxc/issues/16118.
  // Other linters keep their existing single-invocation behavior.
  async function sourceState() {
    const hash = crypto.createHash("sha256");
    for (const file of config.files_to_diff) {
      hash.update(
        await fs.promises.readFile(path.join(sandbox, sourcePrefix, file))
      );
      hash.update("\0");
    }
    return hash.digest("hex");
  }

  let state = maxFixPasses > 1 ? await sourceState() : undefined;
  const seenStates = new Set([state]);
  let ret;
  for (let pass = 1; pass <= maxFixPasses; pass++) {
    const linter = config.chdir
      ? path.resolve(sandbox, config.linter)
      : config.linter;
    ret = childProcess.spawnSync(linter, spawnArgs, {
      stdio: "inherit",
      cwd: path.join(sandbox, config.chdir || "."),
      env: config.env || {},
    });
    if (ret.error) {
      throw ret.error;
    }
    if (ret.signal) {
      throw new Error(`Linter terminated by ${ret.signal}`);
    }
    if (maxFixPasses === 1 || ret.status > 1) break;

    const nextState = await sourceState();
    if (nextState === state) break;
    if (seenStates.has(nextState)) {
      console.error(
        `Linter fixes entered a cycle after ${pass} passes; stopping`
      );
      break;
    }
    seenStates.add(nextState);
    state = nextState;
    if (pass === maxFixPasses) {
      console.error(
        `Linter fixes did not converge after ${maxFixPasses} passes; stopping`
      );
    }
  }

  const diffOut = fs.openSync(config.output, "w");
  const diffBin = process.env["DIFF_BIN"]
    ? path.join(process.env["JS_BINARY__RUNFILES"], process.env["DIFF_BIN"])
    : "diff";

  for (const f of config.files_to_diff) {
    const origF = path.join(process.cwd(), sourcePrefix, f);
    const newF = path.join(sandbox, sourcePrefix, f);
    debug(`diffing ${origF} to ${newF}`);
    // NB: use a/ and b/ prefixes, intended so the result is applied with 'patch -p1'
    const results = childProcess.spawnSync(
      // Note: not using @bazel/runfiles library for lookup because it's a pain to ship dependencies
      diffBin,
      [`--label=a/${f}`, `--label=b/${f}`, "--unified", origF, newF],
      {
        encoding: "utf8",
      }
    );
    debug(results.stdout);
    fs.writeSync(diffOut, results.stdout);
    if (results.error) {
      console.error(results.error);
    }
  }

  fs.closeSync(diffOut);

  return ret.status;
}

(async () => {
  let sandbox;
  try {
    sandbox = path.join(
      await fs.promises.mkdtemp(path.join(os.tmpdir(), "rules_lint_patcher-")),
      process.env.JS_BINARY__WORKSPACE
    );
    // Propagate the exit code of the subprocess so the caller can interpret it.
    process.exitCode = await main(process.argv.slice(2), sandbox);
  } catch (e) {
    console.error(e);
    process.exit(1);
  } finally {
    try {
      if (sandbox) {
        await fs.promises.rm(sandbox, { recursive: true });
      }
    } catch (e) {
      console.error(
        `An error has occurred while removing the sandbox folder at ${sandbox}. Error: ${e}`
      );
    }
  }
})();
