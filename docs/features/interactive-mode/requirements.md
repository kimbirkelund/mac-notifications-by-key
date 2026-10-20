# Interactive mode — Requirements

Behavioral requirements for interactive mode (feature code `IM`). See
[conventions](../../conventions.md) for the ID scheme and [foundations](../../_index.md#foundations)
for `C-*`/`X-*`.

## Mode signal

- **RIM-1 (event) — Overlay signals the active mode and owns input.** When the user runs
  `interactive`, the system shall display a screen-filling borderless window on every Space, above
  every window except the Notification Center panel — which stays on top of it and reachable —
  tinted and bearing no text; shall become the active application and hold keyboard focus; and shall
  keep that overlay visible until interactive mode ends, though focus may leave it when the user
  interacts with the panel. Keyboard and mouse input shall be received by the overlay and shall
  **not** reach the windows beneath it; the panel, being above it, is not covered by this.

- **RIM-2 (state) — The overlay is a translucent tint.** While interactive mode is active, the
  overlay shall be translucent rather than opaque, keeping the desktop visible underneath it so the
  mode reads as a tint over the screen rather than a blackout.

- **RIM-3 (state) — No application presence.** While interactive mode is active, the system shall
  present no Dock icon, no menu bar, and no entry in the window cycler — it holds focus without
  becoming an application the user switches among.

- **RIM-4 (event) — Re-invocation focuses the running mode.** When `interactive` is invoked while
  interactive mode is already active, the system shall bring the existing overlay to the front and
  give it focus rather than drawing a second overlay; the new invocation shall exit `0` and the
  already-running instance shall continue to own the mode.

## Notification Center panel

- **RIM-5 (event) — Open the panel on entering the mode.** When the user runs `interactive`, the
  system shall ensure the Notification Center panel is open — opening it if it is not already — so
  that the notification list and the panel-only controls exist for the duration of the mode rather
  than depending on a banner happening to be on screen.

## Ending the mode

- **RIM-6 (event) — Terminate on signal.** When interactive mode receives `SIGINT` or `SIGTERM`, the
  system shall remove the overlay from the screen, ensure the Notification Center panel is closed,
  and exit `0`, releasing keyboard and mouse input back to the rest of the system. The panel shall
  be closed even if it was already open before the mode was entered — the mode does not restore
  prior panel state. Nothing else closes it: it survives focus changes and this process exiting, so
  leaving it open would outlive the mode.

- **RIM-7 (event) — Terminate on Escape.** When the user presses Escape while the overlay holds
  focus, the system shall end interactive mode with the same teardown as [RIM-6](#ending-the-mode) —
  overlay removed, panel closed, exit `0`. This is the way out that does not depend on an external
  hotkey daemon: the overlay consumes all input, so without a key it honors itself there is no exit
  reachable from the machine's own keyboard.

## Selection and actions

- **RIM-10 (state) — An action panel beside the selected notification.** While interactive mode is
  active and a notification is selected ([RIM-11](#selection-and-actions)), the overlay shall show
  exactly one action panel: immediately to the left of the selected notification, its top edge
  aligned with the notification's, at least as tall as the notification and taller when its entries
  or movement hints need the room, and no wider than its entries need. No other presented
  notification shall have a panel. The panel shall list `Activate`, `Dismiss` (labelled
  `Dismiss this / app / all`), and the names of the actions that notification exposes
  ([RNA-1](../notification-access/requirements.md)), in that order, one entry per line. The panel
  shall not list `Close`, which the `Dismiss` entry already performs.

- **RIM-11 (state) — Exactly one notification is selected.** While interactive mode is active and at
  least one notification is presented, exactly one notification shall be selected; on entering the
  mode the newest is selected. The action panel ([RIM-10](#selection-and-actions)) shall mark the
  selected notification: it sits beside that notification and no other.

- **RIM-12 (event) — Move the selection.** When the user presses Down or `j` while the overlay holds
  focus, the system shall select the next older notification; when Up or `k`, the next newer. At
  either end of the list the selection shall stay where it is (clamp, no wrap).

- **RIM-13 (state) — The panel shows key activators.** While a notification is selected, its action
  panel shall show, to the left of each entry and right-aligned in a column of their own, the key
  that triggers it — a single key, except on the `Dismiss` row. Keys are assigned per panel as
  follows: `Activate` is always Space, shown as `space`, and `Dismiss` is always `d`, shown as
  `d / D / X` together with the app-wide and global keys of [RIM-20](#selection-and-actions). Each
  remaining entry, in listed order, takes the first letter of its name that is not reserved and not
  already assigned in that panel — scanning the name left to right, skipping non-letters — and, if
  no letter of its name is free, the lowest unassigned digit `1`–`9`. Apart from the `Dismiss` row's
  `D` and `X`, activators are shown in **lower case**, and only the unshifted key triggers a letter
  activator — the shifted (upper-case) letter is a different, currently unbound key
  ([RIM-17](#selection-and-actions)), except `D` and `X`, which [RIM-20](#selection-and-actions)
  binds. Reserved keys are `d`, Space, `j`, `k`, Up, Down, and Escape.

- **RIM-14 (event) — Trigger an entry by key.** When the user presses an activator key shown in the
  selected notification's panel while the overlay holds focus, the system shall perform that entry
  on the selected notification: `Dismiss` as `dismiss <n>` does
  ([RNA-4](../notification-access/requirements.md)), `Activate` as `press <n>` does
  ([RNA-6](../notification-access/requirements.md)), and a named action as `action <n> <name>` does
  ([RNA-5](../notification-access/requirements.md)). Interactive mode shall stay active afterwards.

- **RIM-24 (event) — The panel is hidden while an entry is performed.** When the user triggers
  `Activate` on a notification that is not a stack, `Dismiss`, any named action, `D` or `X`
  ([RIM-14](#selection-and-actions), [RIM-20](#selection-and-actions)), the system shall remove the
  action panel from the overlay before performing the entry, and shall redraw it
  ([RIM-15](#selection-and-actions), [RIM-22](#selection-and-actions)) once the entry has completed
  and the notifications presented have been read again, even if none changed. When the user triggers
  `Expand` on a collapsed stack, the system shall keep the action panel.

- **RIM-15 (event) — Selection survives the selected notification going away.** When the selected
  notification is no longer presented — after an entry was performed on it, or because it was
  dismissed elsewhere — the system shall select the notification now at the same position in the
  list, or the last one if the list is shorter, and redraw the action panels to match the
  notifications now presented. If none is left, [RIM-16](#selection-and-actions) applies instead.

- **RIM-22 (event) — The selection follows its notification through list changes.** When the set of
  presented notifications changes while the selected notification is still presented — a
  notification arrives, or one other than the selected goes away — the system shall redraw the
  action panels to match within one second and shall keep the selected notification selected at its
  new position; the newly arrived notification shall not take the selection.

- **RIM-16 (event) — No notifications left ends the mode.** When no notification is presented while
  interactive mode is active — on entering the mode with an empty panel, or once the last one goes
  away — the system shall show the text `No more jobs!` on the overlay, fade the overlay out, and
  then end interactive mode with the same teardown as [RIM-6](#ending-the-mode): overlay removed,
  panel closed, exit `0`. While the label is showing, movement and activator keys shall do nothing;
  Escape and signals shall still end the mode at once. The fade's duration is feature work;
  acceptance only bounds the whole exit.

- **RIM-17 (unwanted) — Unbound key.** If a key is pressed while the overlay holds focus that is
  none of Escape, a movement key, an activator shown in the selected panel, or a global activator
  ([RIM-20](#selection-and-actions)), then the system shall ignore it.

- **RIM-18 (state) — A collapsed stack offers `Expand` instead of `Activate`.** While a presented
  element is a collapsed stack of several notifications from one app, its action panel shall show
  `Expand` in place of `Activate`, on the same key (Space); when triggered, the system shall expand
  the stack so that its members become individually presented notifications, and
  [RIM-15](#selection-and-actions) shall then apply — the selection lands on the member now at the
  stack's position. When `Dismiss` is triggered on a collapsed stack, the system shall dismiss the
  stack as a whole.

- **RIM-19 (retired)** — Mouse activation of panel entries was dropped from the design; the ID is
  not reused.

- **RIM-20 (event) — Clear all and dismiss all for app by upper-case key.** When the user presses
  `X` (Shift+`x`) while the overlay holds focus, the system shall clear every presented
  notification; when `D` (Shift+`d`), dismiss every presented notification from the selected
  notification's app. Both then fall under [RIM-15](#selection-and-actions) or, if nothing is left,
  [RIM-16](#selection-and-actions). The operations performed are `clear-all`
  ([RNA-11](../notification-access/requirements.md)) and `clear-all-for-app`
  ([RNA-12](../notification-access/requirements.md)). Both keys are shown on the panel's `Dismiss`
  row.

- **RIM-23 (state) — The panel shows which moves are possible.** While a notification is selected,
  its action panel shall show, in a column between the entries and the notification, an up-pointing
  mark with `k` beneath it at the top of the panel when a newer notification is presented, and `j`
  with a down-pointing mark beneath it level with the bottom of the selected notification, or just
  below the `k` hint when both are shown and the notification is too short to hold both, when an
  older one is presented; a hint shall be absent whenever the corresponding move
  ([RIM-12](#selection-and-actions)) would leave the selection where it is.

## Demo mode

- **RIM-21 (optional) — Demo notifications in place of Notification Center's.** Where `interactive`
  is invoked with `--demo <file>`, the system shall present the file's notifications in place of
  Notification Center's, draw a placeholder per notification, open and close no panel, and apply
  entries to that list according to whether the file says each entry closes its notification; where
  the file schedules a notification's arrival or departure, the system shall present it only from
  its arrival until its departure, and where the file says an entry on a notification takes some
  seconds, the system shall complete that entry's removal of the notification only after that delay;
  everything else shall behave as without `--demo`. The file's format is the
  [demo file](../../definitions.md).

## Safe failure

- **RIM-8 (unwanted) — No usable display.** If no screen is available when `interactive` is invoked,
  then the system shall report the error on stderr and exit non-zero, rather than crashing on an
  absent main screen.

- **RIM-9 (unwanted) — Missing Accessibility trust.** If `interactive` is invoked while the host
  lacks Accessibility trust ([C-2](../../constraints.md)), then the system shall report the missing
  permission and how to grant it, and exit non-zero without showing the overlay — a mode whose
  notification operations would all fail shall not be entered ([X-4](../../cross-cutting.md)).

## Open seeds (not yet specified)

- **Collapsing a stack.** [RIM-18](#selection-and-actions) expands a stack from the overlay;
  collapsing it again is not specified.
- **Launch on unlock.** Entering the mode when the machine is unlocked is part of the daemon seed in
  [notification-access](../notification-access/requirements.md#open-seeds-not-yet-specified); open
  there is how it coexists with [RIM-4](#mode-signal)'s re-invocation rule.
