# Interactive mode — Acceptance scenarios

BDD scenarios (Gherkin) specifying interactive mode. These `.feature` files **are** the executable
acceptance tests: [cucumber-js](https://github.com/cucumber/cucumber-js) runs them against the
compiled `nbk` binary as a black box, using the step definitions in `acceptance/steps/`.

The twenty-eight unattended scenarios run in the default acceptance run. All but one run in demo
mode ([RIM-21](../requirements.md#demo-mode)) and never touch the real Notification Center; the
exception is the window-order scenario, which needs the real panel. The trust scenario is
`@operator` and runs only attended.

| Scenario                                                                | Validates           | Status                                         |
| ----------------------------------------------------------------------- | ------------------- | ---------------------------------------------- |
| Entering the mode shows the overlay (demo)                              | RIM-1               | ✅                                             |
| The mode keeps no application presence (demo)                           | RIM-3               | ✅                                             |
| Re-invoking does not stack a second overlay (demo)                      | RIM-4               | ✅                                             |
| Terminating on a signal removes the overlay (demo)                      | RIM-6               | ✅                                             |
| Pressing Escape leaves the mode (demo)                                  | RIM-7               | ✅                                             |
| The panel sits above the overlay, untinted                              | RIM-1, RIM-2, RIM-5 | ✅                                             |
| Only the selected notification gets an action panel (demo)              | RIM-10              | ✅                                             |
| Nothing presented on entry ends the mode (demo)                         | RIM-10, RIM-16      | ✅                                             |
| Dismissing the last notification ends the mode (demo)                   | RIM-16              | ✅                                             |
| Escape during the farewell ends the mode at once (demo)                 | RIM-16              | ✅                                             |
| The newest notification is selected on entry (demo)                     | RIM-11              | ✅                                             |
| The selected panel shows lower-case activators (demo)                   | RIM-13              | ✅                                             |
| Moving the selection between notifications (demo)                       | RIM-12              | ✅                                             |
| Movement hints show only where a move is possible (demo)                | RIM-23, RIM-12      | ✅                                             |
| Unbound keys are ignored (demo)                                         | RIM-17              | ✅                                             |
| Pressing d dismisses the selected notification (demo)                   | RIM-14              | ✅                                             |
| The panel hides while an entry removes its notification (demo)          | RIM-24, RIM-21      | ✅                                             |
| Pressing a named action's key performs it (demo)                        | RIM-14              | ✅                                             |
| An action that does not close keeps the notification (demo)             | RIM-14, RIM-21      | ✅                                             |
| Pressing Space activates the selected notification (demo)               | RIM-14              | ✅                                             |
| Pressing X clears every notification and ends the mode (demo)           | RIM-20, RIM-16      | ✅                                             |
| Pressing D dismisses the selected notification's app only (demo)        | RIM-20, RIM-15      | ✅                                             |
| Close is not listed as an entry (demo)                                  | RIM-10              | ✅                                             |
| A collapsed stack offers Expand instead of Activate (demo)              | RIM-18              | ✅                                             |
| Expanding a stack presents its members in its place (demo)              | RIM-18, RIM-15      | ✅                                             |
| An arriving notification keeps the selection on its notification (demo) | RIM-22, RIM-21      | ✅                                             |
| A departing notification keeps the selection on its notification (demo) | RIM-22, RIM-21      | ✅                                             |
| A missing demo file is refused before the overlay (demo)                | RIM-21              | ✅                                             |
| Missing Accessibility trust is refused                                  | RIM-9               | ✅ `@operator` — attended; last run 2026-09-27 |

## What the harness adds

Interactive mode is long-running and graphical, so the harness has six capabilities beyond what
notification access uses. None needs a new framework.

- **A spawned, retained process.** The existing world promisifies `execFile`, which awaits exit;
  interactive mode never exits on its own. The harness spawns it, retains the handle, and awaits a
  promise for the exit status. Cleanup stops any leftover interactive process and closes the panel.
- **Overlay introspection.** System Events can enumerate our own AX windows (existence, position,
  size, and any label as static text) with no extra tooling or permission.
- **A real key event.** `osascript -e 'tell application "System Events" to key code 53'` posts
  Escape. Because it goes to whatever holds focus, the step asserts the overlay is frontmost first —
  otherwise a mistimed keystroke lands in the developer's editor and the failure is misleading.
  System Events reports a bundle-less accessory process as never frontmost, so the frontmost check
  asks the workspace for the active application instead.
- **Notification and panel frames.** The action-panel scenarios read each presented notification's
  position and size from the demo window's placeholders, and our own action-panel groups (their
  position, size, the action names they list, and the texts of their movement hints) from the
  overlay's accessibility windows. Same permission, no new tooling.
- **Fixtures.** Scenarios that need a controlled set of notifications start the mode with
  `--demo <file>`, the path relative to `acceptance/fixtures/`; a fixture may time a notification's
  arrival or departure with `arrivesAfter` / `leavesAfter` seconds. Demo mode draws a placeholder
  per notification, so the harness reads presented notifications from those placeholders instead of
  Notification Center, and never runs `nbk list` in such a scenario.
- **Keystrokes.** Movement and activator keys are posted through System Events, each step first
  asserting the overlay is frontmost so a mistimed key cannot reach another app.

One scenario needs more: window **level** and **alpha** are not exposed through AX, so "panel above
the overlay" and "translucent" need a small helper that dumps `CGWindowListCopyWindowInfo` (owner,
window name, level, front-to-back order, alpha). Owner, level, order and alpha need no permission —
the probe recorded in the [AX reference](../../../notification-center-ax-api.md) read exactly that.
The window **name** is different: for another process's windows it is empty unless the caller has
Screen Recording permission (macOS 10.15 and later). Both steps identify the overlay row by its
window name, so the harness needs Screen Recording permission for this scenario, and without it the
overlay row is not found. The Notification Center row is matched by process, because owner names are
localized. The helper is built alongside `nbk` but is not part of its CLI. A banner produces the
same Notification Center row as the panel, so the window list proves only order; whether the panel
is open always comes from the AX check described in the AX reference.

## Deliberately not covered here

- **RIM-8 (no usable display)** — a screen cannot be removed from under a test. Belongs in the unit
  tier behind a screen-provider seam, not in an acceptance scenario.
- **RIM-1's "on every Space"** — no public API enumerates Spaces; verifying it means driving Mission
  Control or private calls. Accepted as visually verified.
- **RIM-6's "closed even if it was already open before entering"** — no tier proves it; the unit
  tests cover only that the screen release closes the panel, and no real-panel scenario enters the
  mode with the panel already open.
- **RIM-16's "keys are ignored during the farewell"** — the farewell is too brief to probe reliably
  with real key events. Belongs in the unit tier, against the key handling.
- **Tint color and exact opacity** — pixel properties. `RIM-2` is asserted only as "not opaque"; the
  rest is [appearance detail](../requirements.md#open-seeds-not-yet-specified).

## Notes

- **One notification at a time in the real Notification Center.** The harness cannot present a
  second real notification: every notification it delivers is attributed to Script Editor and
  collapses into that app's stack. Behavior that needs several notifications, or notifications with
  chosen actions, is therefore covered by the demo scenarios. The one real-Notification-Center
  scenario covers the panel's window order; opening and closing the panel is covered by the unit and
  AX-integration tiers, and expanding a real stack is proven in the AX-integration tier.
- `@wip` scenarios are excluded from the default run via `tags` in `cucumber.mjs`; the `operator`
  profile excludes them too, so an unimplemented attended scenario cannot fail an attended run.
- Scenarios assert observable state — exit status, window presence, panel state — never macOS copy.
- The tier is environment-dependent (real Notification Center, AX trust, and a screen the mode takes
  over); see [testing](../../../testing.md) gating.
