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

When('I start {string}', function (command) {
  assert.equal(command, 'nbk interactive', `only "nbk interactive" can be started; got: ${command}`)
  this.startInteractive()
})

Given('interactive mode is running', STEP, async function () {
  this.startInteractive()
  await waitForOverlay(this)
  assert.ok(await this.waitForPanel(true), 'expected the Notification Center panel to open')
})

Then('an overlay window covering the screen is present', STEP, async function () {
  await waitForOverlay(this)
})

Then('the overlay is the frontmost application', STEP, async function () {
  await waitForOverlay(this)
  const frontmost = await this.pollUntil(() => this.isInteractiveFrontmost(), SETTLE_MS)
  assert.ok(frontmost, 'expected nbk to be the frontmost application')
})

Then('the overlay shows the mode label', STEP, async function () {
  const wins = await waitForOverlay(this)
  assert.ok(
    wins.some((w) => w.labels.length > 0),
    `expected the overlay to show a label; windows: ${JSON.stringify(wins)}`
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

// Panels settle only after the panel opens, so wait for one per frame.
async function panelsWithFrames(world) {
  let last = { frames: [], panels: [] }
  const paired = await world.pollUntil(async () => {
    const [frames, panels] = [await world.notificationFrames(), await world.actionPanels()]
    last = { frames, panels }
    return frames.length > 0 && panels.length === frames.length ? last : null
  }, SETTLE_MS)
  assert.ok(
    paired,
    `expected one action panel per presented notification; last read: ${JSON.stringify(last)}`
  )
  return paired
}

Then('one action panel is present per presented notification', STEP, async function () {
  await panelsWithFrames(this)
})

Then(
  'each panel lists "Activate", "Dismiss", then that notification\'s actions in order',
  STEP,
  async function () {
    const { frames, panels } = await panelsWithFrames(this)
    const items = await this.listJson()
    frames.forEach((frame, i) => {
      const item = items.find((n) => n.title === frame.title)
      assert.ok(
        item,
        `no listed notification titled ${JSON.stringify(frame.title)}: ${JSON.stringify(items)}`
      )
      assert.deepEqual(
        panels[i].entries,
        ['Activate', 'Dismiss', ...item.actions],
        `panel ${i} does not match notification ${JSON.stringify(frame.title)}`
      )
    })
  }
)

Then(
  'each panel sits to the left of its notification with the same top edge',
  STEP,
  async function () {
    const { frames, panels } = await panelsWithFrames(this)
    frames.forEach((frame, i) => {
      const panel = panels[i]
      const context = `panel ${JSON.stringify(panel)}, notification ${JSON.stringify(frame)}`
      assert.ok(
        panel.x + panel.width <= frame.x,
        `expected the panel left of its notification; ${context}`
      )
      const gap = frame.x - (panel.x + panel.width)
      assert.ok(
        gap <= MAX_GAP_PX,
        `expected the panel immediately left of its notification (gap ${gap} > ${MAX_GAP_PX} px); ${context}`
      )
      assert.ok(
        Math.abs(panel.y - frame.y) <= TOP_EDGE_TOLERANCE_PX,
        `expected the same top edge (±${TOP_EDGE_TOLERANCE_PX} px); ${context}`
      )
    })
  }
)

// Absence has no settle point, so hold it for the window in which panels would be drawn.
const NO_PANEL_HOLD_MS = 1500

Then('no action panel is present', STEP, async function () {
  const deadline = Date.now() + NO_PANEL_HOLD_MS
  do {
    const panels = await this.actionPanels()
    assert.equal(panels.length, 0, `expected no action panel; got: ${JSON.stringify(panels)}`)
  } while (Date.now() < deadline)
})
