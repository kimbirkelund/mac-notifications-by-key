# Interactive mode — Requirements

Behavioral requirements for interactive mode (feature code `IM`). See
[conventions](../../conventions.md) for the ID scheme and [foundations](../../_index.md#foundations)
for `C-*`/`X-*`.

## Mode signal

- **RIM-1 (event) — Overlay signals the active mode and owns input.** When the user runs
  `interactive`, the system shall display a screen-filling borderless window on every Space, above
  all other windows — including the Notification Center panel — tinted and bearing a visible mode
  label; shall become the active application and hold keyboard focus; and shall keep that overlay
  visible and focused until interactive mode ends. Keyboard and mouse input shall be received by the
  overlay and shall **not** reach the windows beneath it.

- **RIM-2 (state) — Notifications stay legible through the overlay.** While interactive mode is
  active, the overlay shall be translucent rather than opaque, so the notifications and the panel it
  covers remain readable through it. The overlay is a tint over the real notifications, never a
  replacement for them.

- **RIM-3 (state) — No application presence.** While interactive mode is active, the system shall
  present no Dock icon, no menu bar, and no entry in the window cycler — it holds focus without
  becoming an application the user switches among.

- **RIM-4 (event) — Re-invocation focuses the running mode.** When `interactive` is invoked while
  interactive mode is already active, the system shall bring the existing overlay to the front and
  give it focus rather than drawing a second overlay; the new invocation shall exit `0` and the
  already-running instance shall continue to own the mode.

## Notification Center panel

- **RIM-5 (event) — Open the panel on entering the mode.** When the user runs `interactive`, the
  system shall open the Notification Center panel, so that the notification list and the panel-only
  controls exist for the duration of the mode rather than depending on a banner happening to be on
  screen. The panel shall be opened unconditionally, whatever was on screen beforehand.

## Ending the mode

- **RIM-6 (event) — Terminate on signal.** When interactive mode receives `SIGINT` or `SIGTERM`, the
  system shall remove the overlay from the screen, close the Notification Center panel, and exit
  `0`, releasing keyboard and mouse input back to the rest of the system. The panel shall be closed
  unconditionally — it is not dismissed by focus changes or by this process exiting, so leaving it
  open would outlive the mode.

- **RIM-7 (event) — Terminate on Escape.** When the user presses Escape while the overlay holds
  focus, the system shall end interactive mode with the same teardown as [RIM-6](#ending-the-mode) —
  overlay removed, panel closed, exit `0`. This is the way out that does not depend on an external
  hotkey daemon: the overlay consumes all input, so without a key it honors itself there is no exit
  reachable from the machine's own keyboard.

## Safe failure

- **RIM-8 (unwanted) — No usable display.** If no screen is available when `interactive` is invoked,
  then the system shall report the error on stderr and exit non-zero, rather than crashing on an
  absent main screen.

- **RIM-9 (unwanted) — Missing Accessibility trust.** If `interactive` is invoked while the host
  lacks Accessibility trust ([C-2](../../constraints.md)), then the system shall report the missing
  permission and how to grant it, and exit non-zero without showing the overlay — a mode whose
  notification operations would all fail shall not be entered ([X-4](../../cross-cutting.md)).

## Open seeds (not yet specified)

- **Reaching notifications while the mode is active.** [RIM-1](#mode-signal) stops clicks from
  reaching the notifications beneath the overlay, so until the overlay offers its own selection and
  action controls the notifications cannot be acted on by mouse at all. The overlay's own controls
  are what close this gap; until they exist the mode is signal-only.
- **Notification selection.** Marking one notification as the current subject and moving that
  selection with the keyboard — which arrives directly, the overlay being focused — including how
  the overlay indicates the selection without redrawing the notification itself.
- **Per-notification action menu.** Surfacing the action names a selected notification exposes
  ([RNA-1](../notification-access/requirements.md)) and invoking one from the overlay.
- **Cross-cutting actions.** `clear-all` and `clear-all-for-app`, both from the overlay and — likely
  first, being simpler to test — as one-shot CLI operations under
  [notification-access](../notification-access/_index.md).
- **Focus on exit.** Nothing is specified about which application becomes frontmost after the
  overlay closes; macOS decides. If landing somewhere unexpected proves annoying in use, restoring
  the application that was frontmost when the mode was entered is the obvious refinement.
- **Live refresh.** How the overlay reacts to notifications arriving or being dismissed while the
  mode is active; overlaps the existing watch/daemon seed in
  [notification-access](../notification-access/requirements.md#open-seeds-not-yet-specified).
- **Window level and opacity assertions.** Most of this feature is acceptance-testable — see the
  [acceptance scenarios](acceptance/_index.md). Two properties are not reachable through AX and need
  a small helper dumping the on-screen window list: `RIM-1`'s stacking above the panel and `RIM-2`'s
  translucency. `RIM-1`'s "on every Space" clause and the tint color have no practical automated
  check at all and are accepted as visually verified.
- **Overlay appearance.** Tint color, label text, font, exact opacity, multi-display behavior
  (mirror on every screen vs. main only). Feature-work detail, deliberately not pinned as acceptance
  criteria beyond [RIM-2](#mode-signal)'s "translucent, not opaque".
