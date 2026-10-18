import { After, AfterAll, Before } from '@cucumber/cucumber'
import { NbkWorld } from './world.mjs'

// Start every real-Notification-Center scenario from a clean slate: dismiss any
// leftover test-app notifications so banner coalescing can't hide what the
// scenario delivers. Clearing before (not after) each scenario means one
// open/close cycle per scenario; what a scenario leaves behind is the next
// scenario's problem, and the run's leftovers go in AfterAll.
// @demo scenarios never touch Notification Center, so they skip the clearing
// and only stop the mode they started.
// timeout: clearing opens and closes the panel, each polling to its own deadline.
Before({ tags: 'not @demo', timeout: 30000 }, async function () {
  await this.clearTestNotifications()
})

// Deliveries must settle here: a delayed one landing during the next scenario's
// clear would survive it.
// timeout: stopping interactive mode polls to its own deadline, above cucumber's 5s default.
After({ tags: 'not @demo', timeout: 30000 }, async function () {
  await this.killAllInteractive()
  await this.settleDeliveries()
})

After({ tags: '@demo', timeout: 30000 }, async function () {
  await this.killAllInteractive()
})

// Restore what the @operator scenario revoked. Runs before the generic After
// (cucumber runs After hooks in reverse definition order), so trust is back
// before the cleanup that relies on it.
// timeout: -1 — blocks on human input to restore trust; cucumber's 5s cap must not apply.
After({ tags: '@operator', timeout: -1 }, async function () {
  // Restore trust so subsequent runs work; loops until doctor confirms.
  await this.operatorSetTrust(true)
})

// No World in a run hook, so build one for the one clear that leaves no test
// notifications behind after the run.
AfterAll({ timeout: 30000 }, async function () {
  const world = new NbkWorld({ attach() {}, log() {}, link() {}, parameters: {} })
  await world.closePanelIfOpen()
  await world.clearTestNotifications()
})
