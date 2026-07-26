# Interactive mode — Acceptance scenarios

BDD scenarios (Gherkin) specifying interactive mode. These `.feature` files **are** the executable
acceptance tests: [cucumber-js](https://github.com/cucumber/cucumber-js) runs them against the
compiled `nbk` binary as a black box, using the step definitions in `acceptance/steps/`.

Every scenario is `@wip` today — the `interactive` subcommand does not exist yet.

| Scenario                                            | Validates    | Status                                   |
| --------------------------------------------------- | ------------ | ---------------------------------------- |
| Entering the mode shows the overlay and opens panel | RIM-1, RIM-5 | 🚧 `@wip` — until `interactive` is built |
| The mode keeps no application presence              | RIM-3        | 🚧 `@wip`                                |
| Re-invoking does not stack a second overlay         | RIM-4        | 🚧 `@wip`                                |
| Terminating on a signal tears everything down       | RIM-6        | 🚧 `@wip`                                |
| Pressing Escape leaves the mode                     | RIM-7        | 🚧 `@wip` — needs the key-event step     |
| The overlay sits above the panel without hiding it  | RIM-1, RIM-2 | 🚧 `@wip` — needs the window-list helper |
| Missing Accessibility trust is refused              | RIM-9        | 🚧 `@wip` `@operator` — attended         |

## What the harness needs

Interactive mode is long-running and graphical, so three additions to `acceptance/support/world.mjs`
are required beyond what notification access uses. None needs a new framework.

- **A spawned, retained process.** The existing world promisifies `execFile`, which awaits exit;
  interactive mode never exits on its own. Needs `spawn`, a retained handle, and a promise for the
  exit status.
- **Overlay introspection.** System Events can enumerate our own AX windows (existence, position,
  size, and the mode label as static text) with no extra tooling or permission.
- **A real key event.** `osascript -e 'tell application "System Events" to key code 53'` posts
  Escape. Because it goes to whatever holds focus, the step asserts the overlay is frontmost first —
  otherwise a mistimed keystroke lands in the developer's editor and the failure is misleading.

One scenario needs more: window **level** and **alpha** are not exposed through AX, so "above the
panel" and "translucent" need a small helper that dumps `CGWindowListCopyWindowInfo` (owner, level,
front-to-back order, alpha). No permission required — the probe recorded in the
[AX reference](../../../notification-center-ax-api.md) read exactly that.

## Deliberately not covered here

- **RIM-8 (no usable display)** — a screen cannot be removed from under a test. Belongs in the unit
  tier behind a screen-provider seam, not in an acceptance scenario.
- **RIM-1's "on every Space"** — no public API enumerates Spaces; verifying it means driving Mission
  Control or private calls. Accepted as visually verified.
- **Tint color and exact opacity** — pixel properties. `RIM-2` is asserted only as "not opaque"; the
  rest is [appearance detail](../requirements.md#open-seeds-not-yet-specified).

## Notes

- `@wip` scenarios are excluded from the default run via `tags` in `cucumber.mjs`; the `operator`
  profile excludes them too, so an unimplemented attended scenario cannot fail an attended run.
- Scenarios assert observable state — exit status, window presence, panel state — never macOS copy.
- The tier is environment-dependent (real Notification Center, AX trust, and a screen the mode takes
  over); see [testing](../../../testing.md) gating.
