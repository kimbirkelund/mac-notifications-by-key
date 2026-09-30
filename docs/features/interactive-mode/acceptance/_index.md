# Interactive mode — Acceptance scenarios

BDD scenarios (Gherkin) specifying interactive mode. These `.feature` files **are** the executable
acceptance tests: [cucumber-js](https://github.com/cucumber/cucumber-js) runs them against the
compiled `nbk` binary as a black box, using the step definitions in `acceptance/steps/`.

The twelve unattended scenarios run in the default acceptance run. The trust scenario is `@operator`
and runs only attended.

| Scenario                                            | Validates    | Status                                         |
| --------------------------------------------------- | ------------ | ---------------------------------------------- |
| Entering the mode shows the overlay and opens panel | RIM-1, RIM-5 | ✅                                             |
| The mode keeps no application presence              | RIM-3        | ✅                                             |
| Re-invoking does not stack a second overlay         | RIM-4        | ✅                                             |
| Terminating on a signal tears everything down       | RIM-6        | ✅                                             |
| Pressing Escape leaves the mode                     | RIM-7        | ✅                                             |
| The panel sits above the overlay, untinted          | RIM-1, RIM-2 | ✅                                             |
| Each presented notification gets an action panel    | RIM-10       | ✅                                             |
| No action panel when nothing is presented           | RIM-10       | ✅                                             |
| The newest notification is selected on entry        | RIM-11       | ⏳ not yet run                                 |
| The selected panel shows lower-case activators      | RIM-13       | ⏳ not yet run                                 |
| Movement keys keep a lone selection in place        | RIM-12       | ⏳ not yet run; two-notification movement live |
| Unbound keys are ignored                            | RIM-17       | ⏳ not yet run                                 |
| Missing Accessibility trust is refused              | RIM-9        | ✅ `@operator` — attended; last run 2026-09-27 |

## What the harness adds

Interactive mode is long-running and graphical, so the harness has five capabilities beyond what
notification access uses. None needs a new framework.

- **A spawned, retained process.** The existing world promisifies `execFile`, which awaits exit;
  interactive mode never exits on its own. The harness spawns it, retains the handle, and awaits a
  promise for the exit status. Cleanup stops any leftover interactive process and closes the panel.
- **Overlay introspection.** System Events can enumerate our own AX windows (existence, position,
  size, and the mode label as static text) with no extra tooling or permission.
- **A real key event.** `osascript -e 'tell application "System Events" to key code 53'` posts
  Escape. Because it goes to whatever holds focus, the step asserts the overlay is frontmost first —
  otherwise a mistimed keystroke lands in the developer's editor and the failure is misleading.
  System Events reports a bundle-less accessory process as never frontmost, so the frontmost check
  asks the workspace for the active application instead.
- **Notification and panel frames.** The action-panel scenarios read each presented notification's
  position and size from Notification Center's AX tree, and our own action-panel groups (their
  position, size, and the action names they list) through System Events. Same permission, no new
  tooling.
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
- **Tint color and exact opacity** — pixel properties. `RIM-2` is asserted only as "not opaque"; the
  rest is [appearance detail](../requirements.md#open-seeds-not-yet-specified).

## Notes

- **One notification at a time.** The harness cannot present a second notification: every
  notification it delivers is attributed to Script Editor and collapses into that app's stack.
  RIM-12 is therefore covered unattended only by one scenario that guards against wrap-around or a
  crash with a single notification, and movement between two notifications is verified live by the
  operator.
- `@wip` scenarios are excluded from the default run via `tags` in `cucumber.mjs`; the `operator`
  profile excludes them too, so an unimplemented attended scenario cannot fail an attended run.
- Scenarios assert observable state — exit status, window presence, panel state — never macOS copy.
- The tier is environment-dependent (real Notification Center, AX trust, and a screen the mode takes
  over); see [testing](../../../testing.md) gating.
