# Interactive mode — Description

**Interactive mode** is the counterpart to the one-shot operations. Those answer "dismiss the newest
notification" when the user already knows what is on screen;
[notification access](../notification-access/_index.md) covers that. Interactive mode answers the
other half: the user presses a hotkey, the desktop visibly changes register to say _notifications
are the subject now_, and from there the user picks one and acts on it. Specified so far: the mode
signal, the action panels, and selecting a notification.

## The mode

- **interactive** — enter the mode: open the Notification Center panel, draw the overlay, take
  focus, and stay running until told to stop. One invocation, hotkey-bindable like every other
  operation ([X-1](../../cross-cutting.md)).
- **Invoking it again** — does not stack a second overlay; the already-running mode is brought
  forward and refocused, and the new invocation exits immediately. A toggle hotkey pressed twice
  cannot leave two overlays on screen.
- **Ending it** — two ways in, two ways out: an interrupt or terminate signal, which is what a
  hotkey bound to "leave notifications mode" sends, or **Escape** on the overlay itself. Either way
  the overlay disappears, the panel is closed, input is released, and the process exits `0`.

## Mental model

```
hotkey ──► nbk interactive ──► panel opened, overlay drawn, takes focus, stays up
                                    │
              all keyboard and mouse input goes to the overlay;
              the windows beneath it receive none of it
                                    │
hotkey ──► signal ──┐
                    ├──────────► overlay gone, panel closed, input released, exit 0
Escape on overlay ──┘
```

## What the overlay is, and is not

The overlay is **not** a notification list. macOS already draws the notifications, with the app
icons, text, and animations the user recognizes; a second copy rendered from data read over AX would
lag the real thing and disagree with it. So the overlay covers the whole screen but shows almost
nothing: a translucent tint and a label naming the mode.

That makes its required properties unusually strict, and each one is observable:

- **Above everything except the panel, on every Space.** It covers full-screen apps and every other
  window, but sits beneath the Notification Center panel, which stays on top of it, untinted and
  reachable; it follows the user between Spaces rather than staying behind on one.
- **Translucent, never opaque.** The overlay is a tint over the desktop, not a blackout: the panel
  sits above it already untinted, and the rest of the screen stays visible in outline through the
  overlay rather than disappearing behind solid black.
- **Takes focus.** Entering the mode makes the overlay the active, focused window. This is what
  later features are built on: once the overlay holds focus, keystrokes arrive at it directly, so
  selecting a notification and invoking its actions needs no system-wide event tap and no
  cooperation from the hotkey daemon.
- **Owns input.** Keyboard and mouse events go to the overlay, not to the windows underneath. While
  the mode is active the desktop is inert.
- **No application presence.** No Dock icon, no menu bar, no entry in the window cycler. It holds
  focus without becoming an application the user switches among.

Two consequences follow, and both matter:

- **The mode really is exclusive.** Because the overlay takes focus and consumes input, "only
  notifications can be acted on" is enforced by the system itself rather than by the hotkey daemon's
  mode keymap. That is the simplification focus buys.
- **Selectable and actionable by keyboard.** The panel sits above the overlay and takes mouse clicks
  directly, so a notification can also be dismissed or opened through the panel's own UI. The
  overlay marks one notification as the current subject, moves that mark with the keyboard it holds,
  and performs the selected panel's entries when their keys are pressed.

## Action panels

For each notification the panel presents, the overlay shows a small **action panel** immediately to
its left, aligned with the notification's top edge. It lists `Activate`, `Dismiss`, and then the
names of that notification's own actions, in that order (RIM-10). The panels stay in step with what
is presented: when a notification arrives or goes away while the mode runs, the panels are redrawn
to match. Exactly one notification is selected at a time, and on entering the mode it is the newest;
its panel is visibly distinct from the others (RIM-11). Down or `j` moves the selection to the next
older notification, Up or `k` to the next newer, and it stops at either end rather than wrapping
(RIM-12). The selected panel shows a key to the left of each entry: Space for `Activate`, `d` for
`Dismiss`, and a lower-case letter for each of the notification's own actions, so `r` and `m` for
`Reply` and `Mark as Read` (RIM-13). Unselected panels show names only. Pressing a shown key
performs that entry on the selected notification: `d` dismisses it, Space activates it, and a named
action's key performs that action. The mode stays running afterwards, so the user can act on the
next notification (RIM-14). Any other key is ignored (RIM-17).

## Why the mode opens the panel

Notification Center's Accessibility surface exists only while a banner is on screen or the panel is
open. A mode that waited for a banner would be useless most of the time it was entered — and the
panel-only controls, including per-app clear and `Clear All`, would never be reachable. So entering
the mode opens the panel outright, giving the mode a stable subject for as long as it runs.

Opening it is cheap and unobtrusive: it is a named action on a public element (the menu bar clock,
which belongs to a menu bar process, not to Notification Center; the AX reference names the process
for each macOS release) and it does not disturb which application has focus. See the
[AX reference](../../notification-center-ax-api.md) for the element and the probe evidence.

Closing it is not optional. The panel is sticky — it survives focus moving elsewhere and it survives
the process that opened it exiting. Whatever opens the panel therefore owns closing it, or the mode
leaves the panel hanging on screen after it is gone.

Both ends are stated as a resulting state rather than an action, because the only control available
is a **toggle** (the menu bar clock). Pressing it blindly on entry would _close_ a panel the user
had already opened, and pressing it blindly on exit would _open_ one that was already shut — leaving
exactly the stranded panel the close exists to prevent. So the mode checks and then acts. What it
does not do is restore prior state: the panel is closed on the way out even if the user had it open
beforehand.

Because the mode is long-running, covers the screen, and swallows input, **the way out is
safety-critical, not a refinement**. A signal ends it, which is what a toggle hotkey sends — but a
mode that could _only_ be left that way would strand anyone whose hotkey daemon isn't running or
isn't configured: nothing on the overlay is clickable and no keystroke reaches anything else, so the
only remaining exit would be killing the process from another session. Hence Escape. Holding focus
is what makes it possible — the overlay already receives every keystroke, so honoring one of them
costs nothing.

## Scope

In scope: entering the mode, opening the Notification Center panel, the overlay that signals the
mode and holds focus, re-invoking while it runs, and leaving the mode again by signal or Escape —
closing the panel on the way out. **Out of scope** (open seeds): `clear-all` / `clear-all-for-app`,
reacting to notifications arriving while the mode is active (beyond redrawing the action panels),
and which application regains focus once the overlay closes.

## Conventions

Honors AX-only (C-1), permission required (C-2), OS resilience (C-3), macOS-only (C-4),
version-selectable access behind a seam (C-5), and all cross-cutting requirements (X-1..X-4) — with
X-2 read as stated there: interactive mode communicates through its overlay, not stdout.
