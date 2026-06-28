// cucumber-js configuration. The .feature files are the executable acceptance
// specs; they live next to the requirements they validate, under
// docs/features/**/acceptance/. Step definitions and the world live in acceptance/.
// @wip scenarios are excluded until their CLI subcommands exist.
export default {
  paths: ['docs/features/**/acceptance/*.feature'],
  import: ['acceptance/support/**/*.mjs', 'acceptance/steps/**/*.mjs'],
  tags: 'not @wip',
  format: ['progress']
}
