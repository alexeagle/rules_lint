// A second fix pass must lint the name introduced by the first pass.
export default {
  meta: { name: "fixture" },
  rules: {
    "two-step-rename": {
      meta: { type: "suggestion", fixable: "code", schema: [] },
      create(context) {
        return {
          Identifier(node) {
            const next = { stageOne: "stageTwo", stageTwo: "stageDone" }[
              node.name
            ];
            if (next) {
              context.report({
                node,
                message: "Rename to {{next}}",
                data: { next },
                fix: (fixer) => fixer.replaceText(node, next),
              });
            }
          },
        };
      },
    },
  },
};
