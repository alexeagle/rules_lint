// Fork of 'stylish' plugin that prints relative paths.
// This allows an editor to navigate to the location of the lint warning even though we present
// eslint with paths underneath a bazel sandbox folder.
// from https://raw.githubusercontent.com/eslint/eslint/refs/tags/v9.15.0/lib/cli-engine/formatters/stylish.js
/**
 * @fileoverview Stylish reporter
 * @author Sindre Sorhus
 */
"use strict";

const util = require("node:util");

/**
 * LOCAL MODIFICATION:
 * To avoid complexity of resolving dependencies, this function vendored from
 * https://raw.githubusercontent.com/eslint/eslint/refs/tags/v9.15.0/lib/shared/text-table.js
 */
function table(rows_, opts) {
  const hsep = "  ";
  const align = opts.align;
  const stringLength = opts.stringLength;

  const sizes = rows_.reduce((acc, row) => {
    row.forEach((c, ix) => {
      const n = stringLength(c);

      if (!acc[ix] || n > acc[ix]) {
        acc[ix] = n;
      }
    });
    return acc;
  }, []);

  return rows_
    .map((row) =>
      row
        .map((c, ix) => {
          const n = sizes[ix] - stringLength(c) || 0;
          const s = Array(Math.max(n + 1, 1)).join(" ");

          if (align[ix] === "r") {
            return s + c;
          }

          return c + s;
        })
        .join(hsep)
        .trimEnd(),
    )
    .join("\n");
}

/**
 * LOCAL MODIFICATION:
 * The eslint dependencies should be loaded from the user's node_modules tree, not from rules_lint.
 */

// This script is used as a command-line flag to eslint, so the command line is "node eslint.js --format this_script.js"
// That means we can grab the path of the eslint entry point, which is beneath its node modules tree.
const eslintEntry = process.argv[1];
// Walk up the tree to the location where eslint normally roots the searchPath of its require() calls
const idx = eslintEntry.lastIndexOf("node_modules");
if (idx < 0) {
  throw new Error(
    "node_modules not found in eslint entry point " + eslintEntry,
  );
}

// Modify the upstream code to pass through an explicit `require.resolve` that starts from eslint
let chalk;
try {
  chalk = require(
    require.resolve("chalk", {
      paths: [eslintEntry.substring(0, idx)],
    }),
  );
} catch (error) {
  if (error.code !== "MODULE_NOT_FOUND") {
    throw error;
  }
  // ESLint 10 no longer depends on chalk. Use Node's built-in styles instead
  // of requiring consumers to add an undeclared formatter dependency.
  const color =
    process.env.FORCE_COLOR !== "0" &&
    Boolean(process.env.FORCE_COLOR || process.stdout.isTTY);
  const style = (formats, text) =>
    color && typeof util.styleText === "function"
      ? util.styleText(formats, String(text), { validateStream: false })
      : String(text);
  chalk = Object.fromEntries(
    ["underline", "red", "yellow", "dim", "reset"].map((format) => {
      const paint = (text) => style(format, text);
      paint.bold = (text) => style([format, "bold"], text);
      return [format, paint];
    }),
  );
}

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
      require("node:path").relative(context.cwd, result.filePath),
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
          String(message.line || 0),
          String(message.column || 0),
          messageType,
          message.message.replace(/([^ ])\.$/u, "$1"),
          chalk.dim(message.ruleId || ""),
        ];
      }),
      {
        align: ["", "r", "l"],
        stringLength(str) {
          return util.stripVTControlCharacters(str).length;
        },
      },
    )
      .split("\n")
      .map((el) =>
        el.replace(/(\d+)\s+(\d+)/u, (m, p1, p2) => chalk.dim(`${p1}:${p2}`)),
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
      ].join(""),
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
        ].join(""),
      );
    }
  }

  // Resets output color, for prevent change on top level
  return total > 0 ? chalk.reset(output) : "";
};
