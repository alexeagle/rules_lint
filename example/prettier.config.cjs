/**
 * @see https://prettier.io/docs/en/configuration.html
 */
const config = {
  tabWidth: 2,
  plugins: [require("prettier-plugin-sql"), require("@prettier/plugin-xml")],
};

module.exports = config;
