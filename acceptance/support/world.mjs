import { setWorldConstructor, World } from '@cucumber/cucumber'
import { execFile, spawn } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'

const run = promisify(execFile)

// The compiled CLI under test. build.ps1 sets NBK_BIN; default to the debug build.
const NBK_BIN = process.env.NBK_BIN ?? '.build/debug/nbk'

// The demo Notification Center stand-in that `nbk interactive --demo` reads.
const DEMO_NC_BIN = process.env.DEMO_NC_BIN ?? path.join(path.dirname(NBK_BIN), 'demo-nc')
const DEMO_NC_PROCESS = path.basename(DEMO_NC_BIN)

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

// Demo files named in scenarios are relative to this directory.
const FIXTURES_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'fixtures')

// The window in which demo-nc draws a placeholder box per notification.
const DEMO_WINDOW_NAME = 'Demo notifications'

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

const AX_GROUP = 'AXGroup'
const AX_STATIC_TEXT = 'AXStaticText'

const hasIdentifier = (node, identifier) =>
  node.identifier === identifier || node.children.some((c) => hasIdentifier(c, identifier))
const MAX_GROUP_WALK_DEPTH = 6
const PANEL_TEXT_DEPTH = 4

const groupsOf = (node) => node.children.filter((c) => c.role === AX_GROUP)
const staticTextsOf = (node) => node.children.filter((c) => c.role === AX_STATIC_TEXT)

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
  const names = rowMajor(texts.filter((t) => t.id !== 'activator' && t.id !== 'hint'))
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

function textsOf(node, depth) {
  const texts = staticTextsOf(node).map((t) => ({
    value: t.value,
    id: t.identifier,
    x: t.x,
    y: t.y,
    height: t.height
  }))
  if (depth > 0) for (const g of groupsOf(node)) texts.push(...textsOf(g, depth - 1))
  return texts
}

// Action panels in an AX window tree: [{x, y, width, height, selected, entries: [{activator, name}]}].
// A panel is an AXGroup identified "action-panel" (its texts gathered at bounded depth), or
// failing that any AXGroup holding static texts. Entries are the non-activator
// texts in row-major order (within 2 px of a row's top share it); each text
// identified "activator" belongs to the nearest entry to its right whose vertical
// span overlaps it, so entries without one carry activator null. Texts identified "hint" are not entries;
// their values are the panel's hints in reading order.
// The demo window holds placeholders, not panels, so it is skipped.
function panelsIn(windows) {
  const out = []
  const walk = (node, depth) => {
    if (depth > MAX_GROUP_WALK_DEPTH) return
    for (const g of groupsOf(node)) {
      const isPanel = g.identifier === 'action-panel'
      const texts = textsOf(g, isPanel ? PANEL_TEXT_DEPTH : 0)
      if (isPanel || texts.length > 0) {
        out.push({
          x: g.x,
          y: g.y,
          width: g.width,
          height: g.height,
          selected: g.selected === true,
          entries: pairEntries(texts),
          hints: rowMajor(texts.filter((t) => t.id === 'hint')).map((t) => t.value)
        })
      } else {
        walk(g, depth + 1)
      }
    }
  }
  for (const w of windows) if (w.title !== DEMO_WINDOW_NAME) walk(w, 1)
  return out
}

// Placeholder boxes in the demo window of an AX window tree, as
// {window: bool, frames: [{title, x, y, width, height}]}. A box is the first AXGroup
// (looking through scroll areas) on a path holding direct static texts; its title is
// the text identified "title", or failing that its first text. `window` is false when no demo window exists, so a
// missing window cannot pass for an empty one.
function demoFramesIn(windows) {
  const result = { window: false, frames: [] }
  const walk = (node, depth) => {
    if (depth > MAX_GROUP_WALK_DEPTH) return
    for (const g of node.children) {
      if (g.role === 'AXScrollArea') {
        walk(g, depth + 1)
        continue
      }
      if (g.role !== AX_GROUP) continue
      const texts = staticTextsOf(g)
      if (texts.length > 0) {
        const titled = texts.find((t) => t.identifier === 'title') ?? texts[0]
        result.frames.push({
          title: titled.value,
          x: g.x,
          y: g.y,
          width: g.width,
          height: g.height
        })
      } else {
        walk(g, depth + 1)
      }
    }
  }
  for (const w of windows) {
    if (w.title !== DEMO_WINDOW_NAME) continue
    result.window = true
    walk(w, 1)
  }
  return result
}

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
export class NbkWorld extends World {
  lastResult = null

  interactive = null

  // Set while interactive mode runs from a demo file: { path, fixture }, where
  // fixture is the parsed file, or null when it is not valid JSON.
  demo = null

  pendingDeliveries = []

  // True once a clear found nothing of ours left and nothing has been delivered since.
  notificationCenterClean = false

  async deliver(title, body = 'acceptance body') {
    this.notificationCenterClean = false
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
    this.notificationCenterClean = false
    await this.openPanelIfClosed()
    try {
      for (let i = 0; i < 30; i++) {
        const items = await this.listJson()
        const idx = items.findIndex((n) => n.app === TEST_APP)
        if (idx === -1) {
          this.notificationCenterClean = true
          return
        }
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

  // A clear is one open/close cycle of the panel, so skip it when the last one
  // found nothing and nothing was delivered since.
  async ensureNoTestNotifications() {
    if (!this.notificationCenterClean) await this.clearTestNotifications()
  }

  // Launch `nbk interactive` and retain it: the mode never exits on its own, so
  // execFile (which awaits exit) cannot drive it.
  startInteractive(args = []) {
    const child = spawn(NBK_BIN, ['interactive', ...args], { stdio: ['ignore', 'ignore', 'pipe'] })
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

  // Spawns demo-nc only; the caller waits for its window, then calls startInteractive(['--demo']).
  startDemoNc(file) {
    const demoPath = path.join(FIXTURES_DIR, file)
    let fixture = null
    try {
      fixture = JSON.parse(fs.readFileSync(demoPath, 'utf8'))
    } catch {}
    const child = spawn(DEMO_NC_BIN, [demoPath], { stdio: ['ignore', 'ignore', 'pipe'] })
    const nc = { child, stderr: '' }
    child.on('error', (e) => (nc.stderr += e.message))
    child.stderr.on('data', (chunk) => (nc.stderr += chunk))
    this.demo = { path: demoPath, fixture, nc }
    return nc
  }

  // The file's notifications as { title, actions: [name], arrivesAfter }, newest first.
  demoNotifications() {
    const notifications = this.demo?.fixture?.notifications
    if (!Array.isArray(notifications)) {
      throw new Error(`demo file has no notifications array: ${this.demo?.path}`)
    }
    return notifications.map((n) => ({
      title: n.title,
      actions: (n.actions ?? []).map((a) => (typeof a === 'string' ? a : a.name)),
      arrivesAfter: n.arrivesAfter ?? 0
    }))
  }

  // Those presented when the mode starts: a notification with arrivesAfter is absent until then.
  demoInitiallyPresented() {
    return this.demoNotifications().filter((n) => n.arrivesAfter === 0)
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

  async killDemoNc() {
    const pids = async () => {
      try {
        const { stdout } = await run('pgrep', ['-x', DEMO_NC_PROCESS])
        return stdout.split('\n').filter(Boolean).map(Number)
      } catch {
        return []
      }
    }
    const signalAll = (sig, list) =>
      list.forEach((pid) => {
        try {
          process.kill(pid, sig)
        } catch {}
      })
    signalAll('SIGTERM', await pids())
    if (await pollUntil(async () => (await pids()).length === 0, 3000)) return
    signalAll('SIGKILL', await pids())
    await pollUntil(async () => (await pids()).length === 0, 2000)
  }

  // Pids of every running `nbk interactive`, retained or not (an orphan from a
  // hung step or an earlier run still owns the screen). Scoped to the interactive
  // subcommand so one-shot nbk commands from other runs are left alone.
  async interactivePids() {
    const out = []
    for (const pid of await this.nbkPids()) {
      try {
        const { stdout: args } = await run('ps', ['-o', 'args=', '-p', String(pid)])
        if (/(^|\s)interactive(\s|$)/.test(args.trim())) out.push(pid)
      } catch {}
    }
    return out
  }

  // SIGTERM (so teardown can close the panel), then SIGKILL whatever remains.
  async killAllInteractive() {
    await this.killInteractive()
    await this.killDemoNc()
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

  // Our windows across every process named like the binary (a re-invocation is a
  // second process): [{pid, name, x, y, width, height, labels}], labels being the
  // non-empty static texts directly under the window.
  async overlayWindows() {
    const out = []
    for (const pid of await this.nbkPids()) {
      for (const w of await this.axTree(pid)) {
        const labels = staticTextsOf(w)
          .map((t) => t.value)
          .filter((v) => typeof v === 'string' && v.trim() !== '')
        out.push({
          pid,
          name: w.title ?? '',
          x: w.x,
          y: w.y,
          width: w.width,
          height: w.height,
          labels
        })
      }
    }
    return out
  }

  async nbkPids() {
    try {
      const { stdout } = await run('pgrep', ['-x', NBK_PROCESS])
      return stdout.split('\n').filter(Boolean).map(Number)
    } catch {
      return []
    }
  }

  async notificationFrames() {
    return JSON.parse(await osascript(NOTIFICATION_FRAMES_SCRIPT, 'JavaScript'))
  }

  async axTree(pid) {
    try {
      const { stdout } = await run(path.join(path.dirname(NBK_BIN), 'axdump'), [String(pid)], {
        maxBuffer: 16 * 1024 * 1024,
        timeout: EXEC_TIMEOUT_MS
      })
      return JSON.parse(stdout)
    } catch (e) {
      if (typeof e.code === 'number') return []
      throw new Error(`axdump ${pid} failed: ${(e.stderr || e.message).toString().trim()}`)
    }
  }

  // Sorted top-down, like the real panel's tree order (newest on top).
  async demoFrames(pid = this.demo.nc.child.pid) {
    const result = demoFramesIn(await this.axTree(pid))
    result.frames.sort((a, b) => a.y - b.y)
    return result
  }

  // What the running mode presents: the demo window's boxes under `--demo`,
  // otherwise the real Notification Center panel's notifications.
  async presentedFrames() {
    return this.demo ? (await this.demoFrames()).frames : this.notificationFrames()
  }

  // Sorted top-down so they pair index-wise with notificationFrames (newest on top).
  async actionPanels(pid = this.interactive.child.pid) {
    const panels = panelsIn(await this.axTree(pid))
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
    const { stdout } = await run('pgrep', ['-x', 'NotificationCenter'])
    const pid = Number(stdout.trim().split('\n')[0])
    if (!pid) throw new Error('NotificationCenter is not running')
    return pid
  }

  // CGWindowList snapshot, front-to-back, from the helper built next to nbk.
  async windowList() {
    const { stdout } = await run(path.join(path.dirname(NBK_BIN), 'windowlist'), [], {
      maxBuffer: 16 * 1024 * 1024
    })
    return JSON.parse(stdout)
  }

  // The panel is the Notification Center window holding the "Edit Widgets" button;
  // banners never hold it. Searched at any depth so a layout shift cannot hide it.
  async isPanelOpen() {
    const windows = await this.axTree(await this.notificationCenterPid())
    return windows.some((w) => hasIdentifier(w, 'widget-editor-button'))
  }

  async waitForPanel(open, timeoutMs = 5000) {
    return pollUntil(async () => (await this.isPanelOpen()) === open, timeoutMs)
  }

  // Several consecutive reads agree: a panel mid-close still reads open for a moment.
  async isPanelSettledOpen() {
    for (let i = 0; i < 3; i++) {
      if (i > 0) await sleep(100)
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

  // Let a closing panel finish first, so the press opens it rather than racing the
  // close. A press can still be swallowed when another app is activating (a scenario
  // that pressed a notification just activated its sender), so press once more if
  // the panel still reads closed; never while it reads open.
  async openPanelIfClosed() {
    if (await this.isPanelSettledOpen()) return
    for (let attempt = 0; attempt < 2; attempt++) {
      await this.waitForPanel(false)
      await this.pressClock('open')
      if (await this.waitForPanel(true)) return
      if (await this.isPanelOpen()) return
    }
    throw new Error('the Notification Center panel did not open')
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
