import { setWorldConstructor, World } from '@cucumber/cucumber'
import { execFile } from 'node:child_process'
import readline from 'node:readline'
import { promisify } from 'node:util'

const run = promisify(execFile)

// The compiled CLI under test. build.ps1 sets NBK_BIN; default to the debug build.
const NBK_BIN = process.env.NBK_BIN ?? '.build/debug/nbk'

// osascript `display notification` is delivered by the Script Editor agent, so all
// test notifications appear under this app. Banner coalescing is per-app, so this
// is the app whose stack we clear to keep the Notification Center deterministic.
const TEST_APP = 'Script Editor'

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

/**
 * Black-box world: delivers real notifications and invokes the nbk binary,
 * capturing exit code / stdout / stderr for assertions. The clear/poll helpers
 * keep the shared, real Notification Center deterministic across scenarios.
 */
class NbkWorld extends World {
  lastResult = null

  pendingDeliveries = []

  async deliver(title, body = 'acceptance body') {
    await run('osascript', ['-e', `display notification "${body}" with title "${title}"`])
  }

  // Fire-and-forget a delivery `delayMs` from now, tracked so the After hook can
  // await it before clearing (avoids a late banner leaking into the next scenario).
  scheduleDelivery(title, delayMs) {
    this.pendingDeliveries.push(sleep(delayMs).then(() => this.deliver(title)))
  }

  async settleDeliveries() {
    await Promise.allSettled(this.pendingDeliveries)
    this.pendingDeliveries = []
  }

  // Substitute for an action with no programmatic API (RNA-9: revoke/grant AX
  // trust). Prompts the human and blocks on Enter. Requires an interactive TTY,
  // so it only runs in the attended `@operator` profile, never in CI.
  async promptOperator(message) {
    if (!process.stdin.isTTY) {
      throw new Error(
        'operator step requires an interactive terminal; run: npx cucumber-js -p operator'
      )
    }
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout })
    try {
      await new Promise((resolve) =>
        rl.question(`\n[operator] ${message}\n[operator] Press Enter when done... `, resolve)
      )
    } finally {
      rl.close()
    }
  }

  // Ground truth for AX trust: `nbk doctor` exits 0 iff trusted (build.ps1 uses
  // the same preflight).
  async isTrusted() {
    return (await this.exec(['doctor'])).code === 0
  }

  // Run nbk without touching lastResult (used by the housekeeping helpers).
  async exec(argv) {
    try {
      const { stdout, stderr } = await run(NBK_BIN, argv, { maxBuffer: 16 * 1024 * 1024 })
      return { code: 0, stdout, stderr }
    } catch (err) {
      return {
        code: typeof err.code === 'number' ? err.code : 1,
        stdout: err.stdout ?? '',
        stderr: err.stderr ?? ''
      }
    }
  }

  async runNbk(argv) {
    this.lastResult = await this.exec(argv)
    return this.lastResult
  }

  async listJson() {
    const r = await this.exec(['list'])
    try {
      const items = JSON.parse(r.stdout || '[]')
      return Array.isArray(items) ? items : []
    } catch {
      return []
    }
  }

  // Dismiss our test app's notifications so a stale stack can't coalesce and hide
  // the notification a scenario delivers. Scoped to TEST_APP to avoid nuking the
  // developer's unrelated notifications. Dismissing shifts indices, so re-list
  // each iteration and always dismiss the first match.
  async clearTestNotifications() {
    for (let i = 0; i < 30; i++) {
      const items = await this.listJson()
      const idx = items.findIndex((n) => n.app === TEST_APP)
      if (idx === -1) return
      await this.exec(['dismiss', String(idx)])
      await sleep(300)
    }
  }

  // Poll `list` until a notification with `title` is present, or timeout. Handles
  // banner render delay and `--wait` returning early on an unrelated notification.
  async waitForTitle(title, timeoutMs = 6000) {
    const deadline = Date.now() + timeoutMs
    for (;;) {
      if ((await this.listJson()).some((n) => n.title === title)) return true
      if (Date.now() >= deadline) return false
      await sleep(300)
    }
  }
}

setWorldConstructor(NbkWorld)
