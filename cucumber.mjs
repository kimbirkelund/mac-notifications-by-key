// cucumber-js configuration. The .feature files are the executable acceptance
// specs; they live next to the requirements they validate, under
// docs/features/**/acceptance/. Step definitions and the world live in acceptance/.
// @wip scenarios are excluded until their CLI subcommands exist. @operator
// scenarios are attended: they substitute a human operator for an action with no
// programmatic API (e.g. revoking Accessibility trust), so they are excluded from
// the default/CI run and invoked on demand via the `operator` profile:
//   npx cucumber-js -p operator
const common = {
  paths: ['docs/features/**/acceptance/*.feature'],
  import: ['acceptance/support/**/*.mjs', 'acceptance/steps/**/*.mjs'],
  format: ['progress']
}

export default { ...common, tags: 'not @wip and not @operator' }
export const operator = { ...common, tags: '@operator' }
