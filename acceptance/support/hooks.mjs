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
