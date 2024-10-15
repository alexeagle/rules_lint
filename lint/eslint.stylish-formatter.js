// Fork of 'stylish' plugin that prints relative paths.
// This allows an editor to navigate to the location of the lint warning even though we present
// eslint with paths underneath a bazel sandbox folder.
// from https://github.com/eslint/eslint/blob/331cf62024b6c7ad4067c14c593f116576c3c861/lib/cli-engine/formatters/stylish.js
/**
 * @fileoverview Stylish reporter
 * @author Sindre Sorhus
 */
"use strict";

/**
 * LOCAL MODIFICATION:
 * The three eslint dependencies should be loaded from the user's node_modules tree, not from rules_lint.
 */

// This script is used as a command-line flag to eslint, so the command line is "node eslint.js --format this_script.js"
// That means we can grab the path of the eslint entry point, which is beneath its node modules tree.
const eslintEntry = process.argv[1];
// Walk up the tree to the location where eslint normally roots the searchPath of its require() calls
const idx = eslintEntry.lastIndexOf("node_modules");
if (idx < 0) {
  throw new Error(
    "node_modules not found in eslint entry point " + eslintEntry
  );
}
const searchPath = eslintEntry.substring(0, idx);
// Modify the upstream code to pass through an explicit `require.resolve` that starts from eslint
const chalk = require(require.resolve("chalk", { paths: [searchPath] })),
  stripAnsi = require(require.resolve("strip-ansi", { paths: [searchPath] })),
  table = require(require.resolve("text-table", { paths: [searchPath] }));

//------------------------------------------------------------------------------
// Helpers
//------------------------------------------------------------------------------

/**
 * Given a word and a count, append an s if count is not one.
 * @param {string} word A word in its singular form.
 * @param {int} count A number controlling whether word should be pluralized.
 * @returns {string} The original word with an s on the end if count is not one.
 */
function pluralize(word, count) {
  return count === 1 ? word : `${word}s`;
}

//------------------------------------------------------------------------------
// Public Interface
//------------------------------------------------------------------------------

module.exports = function (results, context) {
  let output = "\n",
    errorCount = 0,
    warningCount = 0,
    fixableErrorCount = 0,
    fixableWarningCount = 0,
    summaryColor = "yellow";

  results.forEach((result) => {
    const messages = result.messages;

    if (messages.length === 0) {
      return;
    }

    errorCount += result.errorCount;
    warningCount += result.warningCount;
    fixableErrorCount += result.fixableErrorCount;
    fixableWarningCount += result.fixableWarningCount;

    // LOCAL MODIFICATION: print path relative to the working directory
    output += `${chalk.underline(
      require("node:path").relative(context.cwd, result.filePath)
    )}\n`;

    output += `${table(
      messages.map((message) => {
        let messageType;

        if (message.fatal || message.severity === 2) {
          messageType = chalk.red("error");
          summaryColor = "red";
        } else {
          messageType = chalk.yellow("warning");
        }

        return [
          "",
          message.line || 0,
          message.column || 0,
          messageType,
          message.message.replace(/([^ ])\.$/u, "$1"),
          chalk.dim(message.ruleId || ""),
        ];
      }),
      {
        align: ["", "r", "l"],
        stringLength(str) {
          return stripAnsi(str).length;
        },
      }
    )
      .split("\n")
      .map((el) =>
        el.replace(/(\d+)\s+(\d+)/u, (m, p1, p2) => chalk.dim(`${p1}:${p2}`))
      )
      .join("\n")}\n\n`;
  });

  const total = errorCount + warningCount;

  if (total > 0) {
    output += chalk[summaryColor].bold(
      [
        "\u2716 ",
        total,
        pluralize(" problem", total),
        " (",
        errorCount,
        pluralize(" error", errorCount),
        ", ",
        warningCount,
        pluralize(" warning", warningCount),
        ")\n",
      ].join("")
    );

    if (fixableErrorCount > 0 || fixableWarningCount > 0) {
      output += chalk[summaryColor].bold(
        [
          "  ",
          fixableErrorCount,
          pluralize(" error", fixableErrorCount),
          " and ",
          fixableWarningCount,
          pluralize(" warning", fixableWarningCount),
          " potentially fixable with the `--fix` option.\n",
        ].join("")
      );
    }
  }

  // Resets output color, for prevent change on top level
  return total > 0 ? chalk.reset(output) : "";
};
