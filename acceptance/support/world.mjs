import { setWorldConstructor, World } from '@cucumber/cucumber'
import { execFile } from 'node:child_process'
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

  async deliver(title, body = 'acceptance body') {
    await run('osascript', ['-e', `display notification "${body}" with title "${title}"`])
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
