import { Given, When, Then } from '@cucumber/cucumber'
import assert from 'node:assert/strict'

// Interactive mode is graphical and settles asynchronously (the overlay appears,
// the panel toggles, the process exits), so assertions poll to a bounded deadline.
const SETTLE_MS = 5000

// Above cucumber's 5 s default, which a single settle deadline would already exhaust.
const STEP = { timeout: 3 * SETTLE_MS }

function coversAScreen(win, screens) {
  return screens.some((s) => win.width >= s.width && win.height >= s.height)
}

async function waitForOverlay(world) {
  const screens = await world.screenSizes()
  const pid = world.interactive.child.pid
  const found = await world.pollUntil(async () => {
    const wins = (await world.overlayWindows()).filter((w) => w.pid === pid)
    return wins.some((w) => coversAScreen(w, screens)) ? wins : null
  }, SETTLE_MS)
  assert.ok(
    found,
    `expected a screen-covering overlay window; windows: ${JSON.stringify(
      await world.overlayWindows()
    )}; screens: ${JSON.stringify(screens)}; stderr: ${world.interactive.stderr}`
  )
  return found
}

async function assertExitStatus(world, status) {
  const exit = await world.awaitExit(SETTLE_MS)
  assert.ok(exit, `interactive mode did not exit within ${SETTLE_MS} ms`)
  assert.deepEqual(
    { code: exit.code, signal: exit.signal },
    { code: status, signal: null },
    `unexpected exit: ${JSON.stringify(exit)}; stderr: ${world.interactive.stderr}`
  )
}

Given('interactive mode is not running', STEP, async function () {
  await this.killAllInteractive()
  const wins = await this.overlayWindows()
  assert.equal(wins.length, 0, `a stray nbk overlay is present: ${JSON.stringify(wins)}`)
})

Given('interactive mode is running', STEP, async function () {
  this.startInteractive()
  await waitForOverlay(this)
  assert.ok(await this.waitForPanel(true), 'expected the Notification Center panel to open')
})

// Demo mode opens no panel; it is running once every fixture notification has a
// box, so no key can fire before the first redraw.
Given('interactive mode is running with demo file {string}', STEP, async function (file) {
  this.startDemo(file)
  const want = this.demoInitiallyPresented().length
  await waitForOverlay(this)
  let last = null
  const shown = await this.pollUntil(async () => {
    last = await this.demoFrames()
    return last.window && last.frames.length === want
  }, SETTLE_MS)
  assert.ok(
    shown,
    `expected the demo window with ${want} notifications; last read: ${JSON.stringify(last)}; stderr: ${this.interactive.stderr}`
  )
})

Then('an overlay window covering the screen is present', STEP, async function () {
  await waitForOverlay(this)
})

Then('the overlay is the frontmost application', STEP, async function () {
  await waitForOverlay(this)
  const frontmost = await this.pollUntil(() => this.isInteractiveFrontmost(), SETTLE_MS)
  assert.ok(frontmost, 'expected nbk to be the frontmost application')
})

Then('the overlay shows no label', STEP, async function () {
  const wins = await waitForOverlay(this)
  assert.ok(
    wins.every((w) => w.labels.length === 0),
    `expected the overlay to show no label; windows: ${JSON.stringify(wins)}`
  )
})

Then('the overlay shows the label {string}', STEP, async function (label) {
  let last = []
  const shown = await this.pollUntil(async () => {
    last = await this.overlayWindows()
    return last.some((w) => w.labels.includes(label))
  }, SETTLE_MS)
  assert.ok(
    shown,
    `expected an overlay label ${JSON.stringify(label)}; windows: ${JSON.stringify(last)}`
  )
})

Then('the Notification Center panel is open', STEP, async function () {
  assert.ok(await this.waitForPanel(true), 'expected the Notification Center panel to be open')
})

Then('the Notification Center panel is closed', STEP, async function () {
  assert.ok(await this.waitForPanel(false), 'expected the Notification Center panel to be closed')
})

Then('the mode presents no Dock icon and no menu bar', STEP, async function () {
  await waitForOverlay(this)
  const dock = await this.dockItemNames()
  assert.ok(!dock.includes('nbk'), `expected no nbk Dock icon; Dock: ${JSON.stringify(dock)}`)
  assert.equal(await this.nbkMenuBarCount(), 0, 'expected nbk to present no menu bar')
})

const OVERLAY_WINDOW_NAME = 'Notifications'

// One process, not one window: the mode owns the overlay and its action-panels window.
Then('exactly one overlay window is present', async function () {
  const wins = await this.overlayWindows()
  const pids = [...new Set(wins.map((w) => w.pid))]
  assert.deepEqual(
    pids,
    [this.interactive.child.pid],
    `expected every nbk window to belong to this process; got: ${JSON.stringify(wins)}`
  )
  assert.equal(
    wins.filter((w) => w.name === OVERLAY_WINDOW_NAME).length,
    1,
    `expected exactly one window named "${OVERLAY_WINDOW_NAME}"; got: ${JSON.stringify(wins)}`
  )
})

Then('interactive mode is still running', function () {
  assert.ok(
    this.isInteractiveRunning(),
    `interactive mode exited: ${JSON.stringify(this.interactive.exit)}; stderr: ${this.interactive.stderr}`
  )
})

When('interactive mode is sent SIGTERM', function () {
  this.sendSignal('SIGTERM')
})

Then('interactive mode exits with status {int}', STEP, async function (status) {
  await assertExitStatus(this, status)
})

Then('no overlay window is present', STEP, async function () {
  const gone = await this.pollUntil(
    async () => (await this.overlayWindows()).length === 0,
    SETTLE_MS
  )
  assert.ok(gone, `expected no overlay window; got: ${JSON.stringify(await this.overlayWindows())}`)
})

When('I press Escape', async function () {
  await this.pressEscape()
})

When('I press {string}', STEP, async function (key) {
  await pressRecordingSelection(this, key)
})

When('I press the Down arrow', STEP, async function () {
  await pressRecordingSelection(this, 'Down')
})

When('I press the Up arrow', STEP, async function () {
  await pressRecordingSelection(this, 'Up')
})

// The panel's window level. A banner shares it, so this proves order only; that the
// panel is the open window comes from the AX check in 'interactive mode is running'.
const PANEL_LAYER = 21

// Window level and front-to-back order are not exposed through AX; the
// window-list helper reads them from CGWindowList.
Then(
  'the Notification Center panel is above the overlay in the window order',
  STEP,
  async function () {
    const pid = this.interactive.child.pid
    const ncPid = await this.notificationCenterPid()
    const rows = await this.windowList()
    const overlayIdx = rows.findIndex((r) => r.pid === pid && r.name === OVERLAY_WINDOW_NAME)
    const panelIdx = rows.findIndex((r) => r.pid === ncPid && r.layer === PANEL_LAYER)
    assert.ok(
      overlayIdx !== -1,
      `no nbk window named "${OVERLAY_WINDOW_NAME}" in the window list: ${JSON.stringify(rows)}`
    )
    assert.ok(
      panelIdx !== -1,
      `no Notification Center window at layer ${PANEL_LAYER} in the window list: ${JSON.stringify(rows)}`
    )
    assert.ok(
      panelIdx < overlayIdx && rows[panelIdx].layer > rows[overlayIdx].layer,
      `expected the panel above the overlay; panel ${JSON.stringify(
        rows[panelIdx]
      )} at ${panelIdx}, overlay ${JSON.stringify(rows[overlayIdx])} at ${overlayIdx}`
    )
  }
)

Then('the overlay is translucent', async function () {
  const pid = this.interactive.child.pid
  const rows = await this.windowList()
  const row = rows.find((r) => r.pid === pid && r.name === OVERLAY_WINDOW_NAME)
  assert.ok(
    row,
    `no nbk window named "${OVERLAY_WINDOW_NAME}" in the window list: ${JSON.stringify(
      rows.filter((r) => r.pid === pid)
    )}`
  )
  assert.ok(row.alpha < 1, `expected the overlay to be translucent; alpha: ${row.alpha}`)
})

const TOP_EDGE_TOLERANCE_PX = 2

// The layout gap is 8 pt; the slack allows for display scaling.
const MAX_GAP_PX = 20

// The one panel settles only after the panel opens, so wait for it.
async function panelWithFrames(world) {
  let last = { frames: [], panels: [] }
  const paired = await world.pollUntil(async () => {
    const [frames, panels] = [await world.presentedFrames(), await world.actionPanels()]
    last = { frames, panels }
    return frames.length > 0 && panels.length === 1 ? last : null
  }, SETTLE_MS)
  assert.ok(
    paired,
    `expected exactly one action panel beside the presented notifications; last read: ${JSON.stringify(last)}`
  )
  return { frames: paired.frames, panel: paired.panels[0] }
}

// The notification the panel belongs to: the one sharing its top edge.
function alignedFrameIndex(frames, panel) {
  return frames.findIndex((f) => Math.abs(panel.y - f.y) <= TOP_EDGE_TOLERANCE_PX)
}

Then('exactly one action panel is present', STEP, async function () {
  await panelWithFrames(this)
})

Then(
  'the panel lists "Activate", "Dismiss this \\/ app \\/ all", then the selected notification\'s actions in order',
  STEP,
  async function () {
    const { frames, panel } = await panelWithFrames(this)
    const frame = frames[alignedFrameIndex(frames, panel)]
    assert.ok(
      frame,
      `no presented notification shares the panel's top edge; panel ${JSON.stringify(panel)}, frames ${JSON.stringify(frames)}`
    )
    const items = this.demo ? this.demoNotifications() : await this.listJson()
    const item = items.find((n) => n.title === frame.title)
    assert.ok(
      item,
      `no listed notification titled ${JSON.stringify(frame.title)}: ${JSON.stringify(items)}`
    )
    assert.deepEqual(
      panel.entries.map((e) => e.name),
      ['Activate', 'Dismiss this / app / all', ...item.actions],
      `the panel does not match notification ${JSON.stringify(frame.title)}`
    )
  }
)

Then(
  'the panel sits to the left of the selected notification with the same top edge',
  STEP,
  async function () {
    const { frames, panel } = await panelWithFrames(this)
    const frame = frames[alignedFrameIndex(frames, panel)]
    const context = `panel ${JSON.stringify(panel)}, frames ${JSON.stringify(frames)}`
    assert.ok(frame, `expected a notification sharing the panel's top edge; ${context}`)
    assert.ok(
      panel.x + panel.width <= frame.x,
      `expected the panel left of its notification; ${context}`
    )
    const gap = frame.x - (panel.x + panel.width)
    assert.ok(
      gap <= MAX_GAP_PX,
      `expected the panel immediately left of its notification (gap ${gap} > ${MAX_GAP_PX} px); ${context}`
    )
  }
)

Then('the panel is at least as tall as the selected notification', STEP, async function () {
  const { frames, panel } = await panelWithFrames(this)
  const frame = frames[alignedFrameIndex(frames, panel)]
  const context = `panel ${JSON.stringify(panel)}, frames ${JSON.stringify(frames)}`
  assert.ok(frame, `expected a notification sharing the panel's top edge; ${context}`)
  assert.ok(
    panel.height + TOP_EDGE_TOLERANCE_PX >= frame.height,
    `expected the panel at least as tall as its notification; ${context}`
  )
})

// Absence has no settle point, so hold it for the window in which panels would be drawn.
const NO_PANEL_HOLD_MS = 1500

Then('no action panel is present', STEP, async function () {
  const deadline = Date.now() + NO_PANEL_HOLD_MS
  do {
    const panels = await this.actionPanels()
    assert.equal(panels.length, 0, `expected no action panel; got: ${JSON.stringify(panels)}`)
  } while (Date.now() < deadline)
})

// Top-down index of the notification the one selected panel sits beside, or null
// when there is no panel, several, an unselected one, or one beside nothing.
function selectedIndex(frames, panels) {
  if (panels.length !== 1 || !panels[0].selected) return null
  const index = alignedFrameIndex(frames, panels[0])
  return index === -1 ? null : index
}

async function readSelection(world) {
  const [frames, panels] = [await world.presentedFrames(), await world.actionPanels()]
  return { frames, panels, index: selectedIndex(frames, panels) }
}

// A settled read: exactly one selected panel beside a presented notification whenever
// any are presented, and none otherwise.
async function settledSelection(world) {
  let last = { frames: [], panels: [] }
  const settled = await world.pollUntil(async () => {
    last = await readSelection(world)
    if (last.frames.length === 0) return last.panels.length === 0 ? last : null
    return last.index !== null ? last : null
  }, SETTLE_MS)
  assert.ok(
    settled,
    `expected exactly one selected action panel beside a presented notification; last read: ${JSON.stringify(last)}`
  )
  return settled
}

// "The selection is unchanged" compares against the selection just before the
// most recent key press, so the baseline is taken here.
async function pressRecordingSelection(world, key) {
  world.selectionBeforeKey = (await settledSelection(world)).index
  await world.pressKey(key)
}

async function assertSelectedIndex(world, want, describe) {
  let last = { frames: [], panels: [] }
  const ok = await world.pollUntil(async () => {
    last = await readSelection(world)
    return want(last.frames) !== null && last.index === want(last.frames)
  }, SETTLE_MS)
  assert.ok(ok, `expected ${describe} to be selected; last read: ${JSON.stringify(last)}`)
}

async function selectedPanel(world) {
  const { panels, index } = await settledSelection(world)
  assert.notEqual(index, null, `expected a selected panel; panels: ${JSON.stringify(panels)}`)
  return panels[0]
}

Then('exactly one action panel is selected', STEP, async function () {
  const { panels, index } = await settledSelection(this)
  assert.notEqual(
    index,
    null,
    `expected exactly one selected panel; panels: ${JSON.stringify(panels)}`
  )
})

Then('the panel sits beside the topmost notification', STEP, async function () {
  const { frames, panels, index } = await settledSelection(this)
  assert.equal(
    index,
    0,
    `expected the panel beside the topmost notification; frames: ${JSON.stringify(frames)}, panels: ${JSON.stringify(panels)}`
  )
})

Then('the topmost notification is selected', STEP, async function () {
  await assertSelectedIndex(
    this,
    (frames) => (frames.length > 0 ? 0 : null),
    'the topmost notification'
  )
})

function assertActivator(panel, activator, name) {
  const entry = panel.entries.find((e) => e.name === name)
  assert.ok(
    entry,
    `no entry ${JSON.stringify(name)} in the selected panel: ${JSON.stringify(panel)}`
  )
  assert.equal(
    entry.activator,
    activator,
    `expected activator ${JSON.stringify(activator)} before ${JSON.stringify(name)}: ${JSON.stringify(panel)}`
  )
}

Then(
  'the selected panel shows activator {string} before {string}',
  STEP,
  async function (activator, name) {
    assertActivator(await selectedPanel(this), activator, name)
  }
)

Then('the selected panel does not list {string}', STEP, async function (name) {
  const panel = await selectedPanel(this)
  assert.ok(
    !panel.entries.some((e) => e.name === name),
    `expected no entry ${JSON.stringify(name)} in the selected panel: ${JSON.stringify(panel)}`
  )
})

async function assertHint(world, hint, shown) {
  let panel
  await world.pollUntil(async () => {
    panel = await selectedPanel(world)
    return panel.hints.includes(hint) === shown
  }, SETTLE_MS)
  assert.equal(
    panel.hints.includes(hint),
    shown,
    `expected ${shown ? '' : 'no '}hint ${JSON.stringify(hint)} in the selected panel: ${JSON.stringify(panel)}`
  )
}

Then('the panel shows the {string} hint', STEP, async function (hint) {
  await assertHint(this, hint, true)
})

Then('the panel does not show the {string} hint', STEP, async function (hint) {
  await assertHint(this, hint, false)
})

// Nothing marks a key as handled, so hold for a window in which a move would show.
const UNCHANGED_HOLD_MS = 1000

Then('the selection is unchanged', STEP, async function () {
  assert.ok(
    'selectionBeforeKey' in this,
    'no selection was recorded: press a key before asserting it is unchanged'
  )
  const deadline = Date.now() + UNCHANGED_HOLD_MS
  do {
    const read = await readSelection(this)
    assert.equal(
      read.index,
      this.selectionBeforeKey,
      `expected the selection to stay at ${this.selectionBeforeKey}; last read: ${JSON.stringify(read)}`
    )
  } while (Date.now() < deadline)
})

// Under --demo the notifications exist only in the mode, so presence is read from
// its demo window; a read that finds no window proves nothing about absence.
async function demoTitles(world) {
  const read = await world.demoFrames()
  return { read, titles: read.window ? read.frames.map((f) => f.title) : null }
}

// A failed or unparsable list proves nothing about absence, so only a successful read counts.
async function assertGone(world, titles) {
  if (world.demo) {
    world.demoRemoved = [...(world.demoRemoved ?? []), ...titles]
    const arrived = new Set(world.demoArrived ?? [])
    const want = world
      .demoNotifications()
      .filter((n) => n.arrivesAfter === 0 || arrived.has(n.title))
      .map((n) => n.title)
      .filter((t) => !world.demoRemoved.includes(t))
    let last = null
    const gone = await world.pollUntil(async () => {
      const { read, titles: shown } = await demoTitles(world)
      last = read
      return shown !== null && JSON.stringify(shown) === JSON.stringify(want)
    }, SETTLE_MS)
    assert.ok(
      gone,
      `expected exactly ${JSON.stringify(want)} presented once ${JSON.stringify(titles)} are gone; last read: ${JSON.stringify(last)}`
    )
    return
  }
  let last = null
  const gone = await world.pollUntil(async () => {
    last = await world.exec(['list'])
    if (last.code !== 0) return false
    try {
      const items = JSON.parse(last.stdout)
      return Array.isArray(items) && !items.some((n) => titles.includes(n.title))
    } catch {
      return false
    }
  }, SETTLE_MS)
  assert.ok(
    gone,
    `expected a successful list without notifications titled ${JSON.stringify(titles)}; last result: ${JSON.stringify(last)}`
  )
}

Then('the notification titled {string} is no longer presented', STEP, async function (title) {
  await assertGone(this, [title])
})

Then(
  'the notifications titled {string} and {string} are no longer presented',
  STEP,
  async function (first, second) {
    await assertGone(this, [first, second])
  }
)

// Arrivals are observable only under --demo, as departures are.
Then('the notification titled {string} becomes presented', STEP, async function (title) {
  assert.ok(this.demo, 'presence is only observable under --demo')
  let last = null
  const presented = await this.pollUntil(async () => {
    const { read, titles } = await demoTitles(this)
    last = read
    return titles !== null && titles.includes(title)
  }, SETTLE_MS)
  assert.ok(
    presented,
    `expected a notification titled ${JSON.stringify(title)} to become presented; last read: ${JSON.stringify(last)}`
  )
  this.demoArrived = [...(this.demoArrived ?? []), title]
})

// Nothing marks a non-closing entry as done, so hold for a window in which a removal would show.
Then('the notification titled {string} is still presented', STEP, async function (title) {
  assert.ok(this.demo, 'presence is only observable under --demo')
  const deadline = Date.now() + UNCHANGED_HOLD_MS
  do {
    const { read, titles } = await demoTitles(this)
    assert.ok(
      titles?.includes(title),
      `expected a notification titled ${JSON.stringify(title)} to stay presented; read: ${JSON.stringify(read)}`
    )
  } while (Date.now() < deadline)
})

// Positions count top-down from 1, as the scenario reads the stack.
Then('the notification at position {int} is selected', STEP, async function (position) {
  await assertSelectedIndex(
    this,
    (frames) => (position >= 1 && position <= frames.length ? position - 1 : null),
    `the notification at position ${position}`
  )
})
