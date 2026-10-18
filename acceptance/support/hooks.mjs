import { Before, After } from '@cucumber/cucumber'

// Start and end every real-Notification-Center scenario from a clean slate:
// dismiss any leftover test-app notifications so banner coalescing can't hide
// what a scenario delivers, and don't leave test notifications behind afterwards.
// @demo scenarios never touch Notification Center, so they skip the clearing
// (which opens and closes the panel) and only stop the mode they started.
// timeout: clearing opens and closes the panel, each polling to its own deadline.
Before({ tags: 'not @demo', timeout: 30000 }, async function () {
  await this.clearTestNotifications()
})

// timeout: stopping interactive mode and waiting for the panel to close each poll
// to their own deadline, which together exceed cucumber's 5s default.
After({ tags: 'not @demo', timeout: 30000 }, async function () {
  await this.killAllInteractive()
  await this.closePanelIfOpen()
  await this.settleDeliveries()
  await this.clearTestNotifications()
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
