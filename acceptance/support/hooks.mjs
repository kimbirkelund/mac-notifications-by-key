import { Before, After } from '@cucumber/cucumber'

// Start and end every scenario from a clean slate: dismiss any leftover test-app
// notifications so banner coalescing can't hide what a scenario delivers, and
// don't leave test notifications behind afterwards.
Before(async function () {
  await this.clearTestNotifications()
})

After(async function () {
  await this.settleDeliveries()
  await this.clearTestNotifications()
})

// Restore what the @operator scenario revoked. Runs before the generic After
// (cucumber runs After hooks in reverse definition order), so trust is back
// before the cleanup that relies on it.
After({ tags: '@operator' }, async function () {
  // Restore trust so subsequent runs work; loops until doctor confirms.
  await this.operatorSetTrust(true)
})
