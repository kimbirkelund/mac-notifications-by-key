import { setWorldConstructor, World } from '@cucumber/cucumber'
import { execFile, spawn } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { promisify } from 'node:util'

const run = promisify(execFile)

// The compiled CLI under test. build.ps1 sets NBK_BIN; default to the debug build.
const NBK_BIN = process.env.NBK_BIN ?? '.build/debug/nbk'

// osascript `display notification` is delivered by the Script Editor agent, so all
// test notifications appear under this app. Banner coalescing is per-app, so this
// is the app whose stack we clear to keep the Notification Center deterministic.
const TEST_APP = 'Script Editor'

// No one-shot nbk command should run this long; one that does (e.g. an accidental
// second interactive overlay) is killed rather than left owning the screen.
const EXEC_TIMEOUT_MS = 20000

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// Interactive mode shows up in System Events under the executable's name.
const NBK_PROCESS = path.basename(NBK_BIN)

// Poll `probe` until it returns a truthy value or the deadline passes; returns the
// last value either way so callers can assert on it with context.
async function pollUntil(probe, timeoutMs = 5000, intervalMs = 200) {
  const deadline = Date.now() + timeoutMs
  for (;;) {
    const value = await probe()
    if (value || Date.now() >= deadline) return value
    await sleep(intervalMs)
  }
}

async function osascript(script, language = 'AppleScript') {
  const { stdout } = await run('osascript', ['-l', language, '-e', script])
  return stdout.trim()
}

// The Notification Center panel is the NC AXSystemDialog window holding the
// "Edit Widgets" button; banners are AXSystemDialog windows too, but never hold it.
// The button is searched at any depth (bounded) so a layout shift cannot hide it.
const PANEL_OPEN_SCRIPT = `
on hasPanelButton(el, depth)
  if depth > 8 then return false
  tell application "System Events"
    set kids to {}
    try
      set kids to UI elements of el
    end try
    repeat with k in kids
      try
        if role of k is "AXButton" and value of attribute "AXIdentifier" of k is "widget-editor-button" then return true
      end try
      if my hasPanelButton(k, depth + 1) then return true
    end repeat
  end tell
  return false
end hasPanelButton

tell application "System Events"
  if not (exists application process "NotificationCenter") then return false
  set ws to {}
  try
    set ws to every window of application process "NotificationCenter"
  end try
end tell
repeat with w in ws
  try
    tell application "System Events" to set sr to subrole of w
    if sr is "AXSystemDialog" then
      if my hasPanelButton(w, 1) then return true
    end if
  end try
end repeat
return false`

// The clock menu extra toggles the panel. Found by identifier under MenuBarAgent
// (macOS 27), falling back to ControlCenter (earlier releases).
const PRESS_CLOCK_SCRIPT = `
tell application "System Events"
  repeat with procName in {"MenuBarAgent", "ControlCenter"}
    if exists application process procName then
      tell application process procName
        repeat with bar in menu bars
          set candidates to menu bar items of bar
          repeat with g in groups of bar
            set candidates to candidates & (menu bar items of g)
          end repeat
          repeat with m in candidates
            try
              if value of attribute "AXIdentifier" of m is "com.apple.menuextra.clock" then
                perform action "AXPress" of m
                return true
              end if
            end try
          end repeat
        end repeat
      end tell
    end if
  end repeat
  return false
end tell`

// Our overlay windows across every process named like the binary (a re-invocation
// is a second process), as JSON [{pid, name, x, y, width, height, labels}].
const OVERLAY_WINDOWS_SCRIPT = `
const se = Application('System Events')
const out = []
for (const p of se.applicationProcesses.whose({ name: ${JSON.stringify(NBK_PROCESS)} })()) {
  const pid = p.unixId()
  for (const w of p.windows()) {
    const [x, y] = w.position()
    const [width, height] = w.size()
    let labels = []
    try {
      labels = w.staticTexts.value().filter((v) => typeof v === 'string' && v.trim() !== '')
    } catch (e) {}
    let name = ''
    try {
      name = w.name() ?? ''
    } catch (e) {}
    out.push({ pid, name, x, y, width, height, labels })
  }
}
JSON.stringify(out)`

// Notification frames in the NC panel, in tree order (newest first), as JSON
// [{title, x, y, width, height}]. A notification is an AXGroup exposing AXPress,
// matched pre-order and descended into, as nbk does (stack members nest);
// the panel is the AXSystemDialog window holding the "Edit Widgets" button.
const NOTIFICATION_FRAMES_SCRIPT = `
const se = Application('System Events')
const attr = (el, name) => {
  try {
    return el.attributes.byName(name).value()
  } catch (e) {
    return null
  }
}
function walk(el, depth, acc) {
  if (depth > 10) return
  let kids = []
  try {
    kids = el.uiElements()
  } catch (e) {}
  for (const k of kids) {
    let role = null
    try {
      role = k.role()
    } catch (e) {}
    if (role === 'AXButton' && attr(k, 'AXIdentifier') === 'widget-editor-button') acc.isPanel = true
    let actions = []
    if (role === 'AXGroup') {
      try {
        actions = k.actions.name()
      } catch (e) {}
    }
    if (actions.includes('AXPress')) {
      const [x, y] = k.position()
      const [width, height] = k.size()
      let title = null
      try {
        for (const t of k.staticTexts()) {
          if (attr(t, 'AXIdentifier') === 'title') title = t.value()
        }
      } catch (e) {}
      acc.frames.push({ title, x, y, width, height })
    }
    walk(k, depth + 1, acc)
  }
}
let out = []
if (se.applicationProcesses.whose({ name: 'NotificationCenter' }).length > 0) {
  for (const w of se.applicationProcesses.byName('NotificationCenter').windows()) {
    let sr = null
    try {
      sr = w.subrole()
    } catch (e) {}
    if (sr !== 'AXSystemDialog') continue
    const acc = { isPanel: false, frames: [] }
    walk(w, 1, acc)
    if (acc.isPanel) {
      out = acc.frames
      break
    }
  }
}
JSON.stringify(out)`

// Action panels drawn by one nbk process, as JSON
// [{x, y, width, height, selected, entries: [{activator, name}]}]. A panel is an
// AXGroup identified "action-panel" (its texts gathered at any bounded depth), or
// failing that any AXGroup holding static texts. Entries are the non-activator
// texts in row-major order (within 2 px of a row's top share it); each text
// identified "activator" belongs to the nearest entry to its right whose vertical
// span overlaps it, so entries without one carry activator null.
const actionPanelsScript = (pid) => `
const se = Application('System Events')
const attr = (el, name) => {
  try {
    return el.attributes.byName(name).value()
  } catch (e) {
    return null
  }
}
function rowMajor(texts) {
  const rows = []
  for (const t of [...texts].sort((a, b) => a.y - b.y)) {
    const row = rows[rows.length - 1]
    if (row && t.y - row[0].y <= 2) row.push(t)
    else rows.push([t])
  }
  return rows.flatMap((row) => row.sort((a, b) => a.x - b.x))
}
function pairEntries(texts) {
  const names = rowMajor(texts.filter((t) => t.id !== 'activator'))
  const entries = names.map((t) => ({ activator: null, name: t.value }))
  for (const a of texts.filter((t) => t.id === 'activator')) {
    let best = -1
    names.forEach((t, i) => {
      const overlaps = t.y < a.y + a.height && a.y < t.y + t.height
      if (overlaps && t.x >= a.x && (best === -1 || t.x < names[best].x)) best = i
    })
    if (best !== -1) entries[best].activator = a.value
  }
  return entries
}
function textsOf(el, depth) {
  let texts = []
  try {
    texts = el.staticTexts().map((t) => {
      const [x, y] = t.position()
      const [, height] = t.size()
      return { value: t.value(), id: attr(t, 'AXIdentifier'), x, y, height }
    })
  } catch (e) {}
  if (depth > 0) {
    let groups = []
    try {
      groups = el.groups()
    } catch (e) {}
    for (const g of groups) texts = texts.concat(textsOf(g, depth - 1))
  }
  return texts
}
function walk(el, depth, out) {
  if (depth > 6) return
  let groups = []
  try {
    groups = el.groups()
  } catch (e) {}
  for (const g of groups) {
    const isPanel = attr(g, 'AXIdentifier') === 'action-panel'
    const texts = textsOf(g, isPanel ? 4 : 0)
    if (isPanel || texts.length > 0) {
      const [x, y] = g.position()
      const [width, height] = g.size()
      const selected = attr(g, 'AXSelected') === true
      out.push({ x, y, width, height, selected, entries: pairEntries(texts) })
    } else {
      walk(g, depth + 1, out)
    }
  }
}
const out = []
for (const p of se.applicationProcesses.whose({ unixId: ${Number(pid)} })()) {
  for (const w of p.windows()) walk(w, 1, out)
}
JSON.stringify(out)`

// System Events reports frontmost false for a bundle-less accessory process even
// while it is the active application; NSWorkspace reports the truth.
const FRONTMOST_PID_SCRIPT = `
ObjC.import('AppKit')
$.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier`

const KEY_CODES = { Escape: 53, Space: 49, Down: 125, Up: 126 }

const SCREEN_SIZES_SCRIPT = `
ObjC.import('AppKit')
const screens = $.NSScreen.screens
const out = []
for (let i = 0; i < screens.count; i++) {
  const f = screens.objectAtIndex(i).frame
  out.push({ width: f.size.width, height: f.size.height })
}
JSON.stringify(out)`

/**
 * Black-box world: delivers real notifications and invokes the nbk binary,
 * capturing exit code / stdout / stderr for assertions. The clear/poll helpers
 * keep the shared, real Notification Center deterministic across scenarios.
 */
class NbkWorld extends World {
  lastResult = null

  interactive = null

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
  // trust). Blocks until the operator presses Enter. Reads the controlling
  // terminal (/dev/tty) with a synchronous read rather than process.stdin, which
  // cucumber detaches — so the wait is real, not skipped. No tty (CI) → throws,
  // which is why the scenario is @operator and never runs unattended.
  async promptOperator(message) {
    let fd
    try {
      fd = fs.openSync('/dev/tty', 'r')
    } catch {
      throw new Error(
        'operator step requires an interactive terminal (/dev/tty); run: npx cucumber-js -p operator'
      )
    }
    process.stdout.write(`\n[operator] ${message}\n[operator] Press Enter when done... `)
    const buf = Buffer.alloc(1)
    try {
      for (;;) {
        let n
        try {
          n = fs.readSync(fd, buf, 0, 1, null)
        } catch (err) {
          if (err.code === 'EAGAIN') continue
          throw err
        }
        if (n === 0 || buf[0] === 0x0a) break
      }
    } finally {
      fs.closeSync(fd)
    }
  }

  // Ground truth for AX trust: `nbk doctor` exits 0 iff trusted (build.ps1 uses
  // the same preflight).
  async isTrusted() {
    return (await this.exec(['doctor'])).code === 0
  }

  // Drive the operator until nbk's trust state matches `wantTrusted`, using
  // `nbk doctor` as ground truth. We deliberately don't name the app that holds
  // the grant: with a terminal multiplexer / process reparenting it can't be
  // detected reliably (TERM_PROGRAM goes stale, the ppid chain breaks). Instead
  // the loop re-checks after each prompt and nags until doctor agrees, so a wrong
  // toggle can't silently pass.
  async operatorSetTrust(wantTrusted) {
    const verb = wantTrusted ? 'Grant' : 'Revoke'
    const where = 'System Settings -> Privacy & Security -> Accessibility'
    let attempt = 0
    while ((await this.isTrusted()) !== wantTrusted) {
      const message =
        attempt === 0
          ? `${verb} Accessibility trust for the terminal application hosting this test run — ` +
            `the entry under ${where} that governs it — then return here.`
          : `nbk still reports ${wantTrusted ? 'untrusted' : 'trusted'}: the wrong entry was ` +
            `toggled, or the change has not applied yet. Adjust the correct entry and return here.`
      await this.promptOperator(message)
      attempt++
    }
  }

  // Run nbk without touching lastResult (used by the housekeeping helpers).
  async exec(argv) {
    try {
      const { stdout, stderr } = await run(NBK_BIN, argv, {
        maxBuffer: 16 * 1024 * 1024,
        timeout: EXEC_TIMEOUT_MS,
        killSignal: 'SIGKILL'
      })
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
  // developer's unrelated notifications. Runs with the panel open, since a closed
  // panel exposes only banners and history would survive. A collapsed stack offers
  // no Close, only Clear All. Dismissing shifts indices, so re-list each iteration
  // and always act on the first match. Leaves the panel closed.
  async clearTestNotifications() {
    await this.openPanelIfClosed()
    try {
      for (let i = 0; i < 30; i++) {
        const items = await this.listJson()
        const idx = items.findIndex((n) => n.app === TEST_APP)
        if (idx === -1) return
        const argv =
          !items[idx].actions.includes('Close') && items[idx].actions.includes('Clear All')
            ? ['action', String(idx), 'Clear All']
            : ['dismiss', String(idx)]
        await this.exec(argv)
        await sleep(300)
      }
      throw new Error(
        `could not clear ${TEST_APP} notifications: ${JSON.stringify(await this.listJson())}`
      )
    } finally {
      await this.closePanelIfOpen()
    }
  }

  // Launch `nbk interactive` and retain it: the mode never exits on its own, so
  // execFile (which awaits exit) cannot drive it.
  startInteractive() {
    const child = spawn(NBK_BIN, ['interactive'], { stdio: ['ignore', 'ignore', 'pipe'] })
    const proc = { child, stderr: '', exit: null }
    child.stderr.on('data', (chunk) => (proc.stderr += chunk))
    proc.exitPromise = new Promise((resolve) => {
      child.on('error', (err) => {
        proc.exit = { code: null, signal: null, error: err.message }
        resolve(proc.exit)
      })
      child.on('exit', (code, signal) => {
        proc.exit = { code, signal }
        resolve(proc.exit)
      })
    })
    this.interactive = proc
    return proc
  }

  sendSignal(sig) {
    this.interactive.child.kill(sig)
  }

  // Resolves to { code, signal } or null if the process is still running at the deadline.
  async awaitExit(timeoutMs = 5000) {
    const proc = this.interactive
    return Promise.race([proc.exitPromise, sleep(timeoutMs).then(() => proc.exit)])
  }

  isInteractiveRunning() {
    return this.interactive !== null && this.interactive.exit === null
  }

  async killInteractive() {
    const proc = this.interactive
    if (proc === null) return
    if (proc.exit === null) {
      proc.child.kill('SIGTERM')
      if ((await this.awaitExit(3000)) === null) {
        proc.child.kill('SIGKILL')
        await proc.exitPromise
      }
    }
    this.interactive = null
  }

  // Pids of every running `nbk interactive`, retained or not (an orphan from a
  // hung step or an earlier run still owns the screen). Scoped to the interactive
  // subcommand so one-shot nbk commands from other runs are left alone.
  async interactivePids() {
    try {
      const { stdout } = await run('pgrep', ['-x', NBK_PROCESS])
      const pids = stdout.split('\n').filter(Boolean).map(Number)
      const out = []
      for (const pid of pids) {
        try {
          const { stdout: args } = await run('ps', ['-o', 'args=', '-p', String(pid)])
          if (/(^|\s)interactive(\s|$)/.test(args.trim())) out.push(pid)
        } catch {}
      }
      return out
    } catch {
      return []
    }
  }

  // SIGTERM (so teardown can close the panel), then SIGKILL whatever remains.
  async killAllInteractive() {
    await this.killInteractive()
    const signalAll = (sig, pids) =>
      pids.forEach((pid) => {
        try {
          process.kill(pid, sig)
        } catch {}
      })
    signalAll('SIGTERM', await this.interactivePids())
    if (await pollUntil(async () => (await this.interactivePids()).length === 0, 3000)) return
    signalAll('SIGKILL', await this.interactivePids())
    await pollUntil(async () => (await this.interactivePids()).length === 0, 2000)
  }

  async overlayWindows() {
    return JSON.parse(await osascript(OVERLAY_WINDOWS_SCRIPT, 'JavaScript'))
  }

  async notificationFrames() {
    return JSON.parse(await osascript(NOTIFICATION_FRAMES_SCRIPT, 'JavaScript'))
  }

  // Sorted top-down so they pair index-wise with notificationFrames (newest on top).
  async actionPanels(pid = this.interactive.child.pid) {
    const panels = JSON.parse(await osascript(actionPanelsScript(pid), 'JavaScript'))
    return panels.sort((a, b) => a.y - b.y)
  }

  async screenSizes() {
    return JSON.parse(await osascript(SCREEN_SIZES_SCRIPT, 'JavaScript'))
  }

  async isInteractiveFrontmost() {
    return (
      Number(await osascript(FRONTMOST_PID_SCRIPT, 'JavaScript')) === this.interactive.child.pid
    )
  }

  async dockItemNames() {
    const names = await osascript(
      'tell application "System Events" to get name of UI elements of list 1 of application process "Dock"'
    )
    return names.split(', ')
  }

  async nbkMenuBarCount() {
    const pid = this.interactive.child.pid
    return Number(
      await osascript(
        `tell application "System Events" to count menu bars of (first application process whose unix id is ${pid})`
      )
    )
  }

  // Keys go to whatever holds focus, so refuse to post one unless we do. `spec` is
  // a named key (Escape, Up, Down, Space) or a single character typed as-is.
  async pressKey(spec) {
    if (!(await this.isInteractiveFrontmost())) {
      throw new Error(
        `refusing to post ${JSON.stringify(spec)}: interactive mode is not the frontmost application`
      )
    }
    const keyCode = KEY_CODES[spec === ' ' ? 'Space' : spec]
    if (keyCode !== undefined) {
      await osascript(`tell application "System Events" to key code ${keyCode}`)
    } else if (spec.length === 1) {
      await osascript(`tell application "System Events" to keystroke ${JSON.stringify(spec)}`)
    } else {
      throw new Error(`unknown key: ${JSON.stringify(spec)}`)
    }
  }

  async pressEscape() {
    await this.pressKey('Escape')
  }

  // Window-list owner names are localized ("Notification Centre"), so rows are
  // matched by pid; the System Events process name is the executable's.
  async notificationCenterPid() {
    return Number(
      await osascript(
        'tell application "System Events" to get unix id of application process "NotificationCenter"'
      )
    )
  }

  // CGWindowList snapshot, front-to-back, from the helper built next to nbk.
  async windowList() {
    const { stdout } = await run(path.join(path.dirname(NBK_BIN), 'windowlist'), [], {
      maxBuffer: 16 * 1024 * 1024
    })
    return JSON.parse(stdout)
  }

  async isPanelOpen() {
    return (await osascript(PANEL_OPEN_SCRIPT)) === 'true'
  }

  async waitForPanel(open, timeoutMs = 5000) {
    return pollUntil(async () => (await this.isPanelOpen()) === open, timeoutMs)
  }

  // Several consecutive reads agree: a panel mid-close still reads open for a moment.
  async isPanelSettledOpen() {
    for (let i = 0; i < 3; i++) {
      if (i > 0) await sleep(250)
      if (!(await this.isPanelOpen())) return false
    }
    return true
  }

  async pressClock(purpose) {
    if ((await osascript(PRESS_CLOCK_SCRIPT)) !== 'true') {
      throw new Error(`cannot ${purpose} the Notification Center panel: clock menu extra not found`)
    }
  }

  // Never blind-toggle: the clock extra flips state, so pressing it on a closed or
  // closing panel would open it and strand it for the next scenario.
  async closePanelIfOpen() {
    if (!(await this.isPanelSettledOpen())) return
    await this.pressClock('close')
    if (!(await this.waitForPanel(false))) {
      throw new Error('the Notification Center panel did not close')
    }
  }

  // Let a closing panel finish first, so the press opens it rather than racing the close.
  async openPanelIfClosed() {
    if (await this.isPanelSettledOpen()) return
    await this.waitForPanel(false)
    await this.pressClock('open')
    if (!(await this.waitForPanel(true))) {
      throw new Error('the Notification Center panel did not open')
    }
  }

  pollUntil(probe, timeoutMs, intervalMs) {
    return pollUntil(probe, timeoutMs, intervalMs)
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
