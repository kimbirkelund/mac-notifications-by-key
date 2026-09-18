# Interactive mode — Description

**Interactive mode** is the counterpart to the one-shot operations. Those answer "dismiss the newest
notification" when the user already knows what is on screen;
[notification access](../notification-access/_index.md) covers that. Interactive mode answers the
other half: the user presses a hotkey, the desktop visibly changes register to say _notifications
are the subject now_, and from there the user picks one and acts on it. Only the mode signal — the
overlay itself — is specified so far.

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

- **Above everything, on every Space.** It covers full-screen apps and the Notification Center panel
  alike, and follows the user between Spaces rather than staying behind on one.
- **Translucent, never opaque.** Covering the panel is not hiding it: the overlay is a tint, so the
  notifications underneath stay readable through it. This is what lets the overlay sit on top
  without concealing its own subject.
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
- **Exclusive means unreachable, for now.** The same property that blocks stray input also blocks
  clicks from reaching the notifications beneath the overlay. Until the overlay offers its own
  selection and action controls, the mode is signal-only: it says "notifications mode" without yet
  providing a way to act. The controls are the next slice.

## Why the mode opens the panel

Notification Center's Accessibility surface exists only while a banner is on screen or the panel is
open. A mode that waited for a banner would be useless most of the time it was entered — and the
panel-only controls, including per-app clear and `Clear All`, would never be reachable. So entering
the mode opens the panel outright, giving the mode a stable subject for as long as it runs.

Opening it is cheap and unobtrusive: it is a named action on a public element (the menu bar clock,
which belongs to ControlCenter rather than Notification Center) and it does not disturb which
application has focus. See the [AX reference](../../notification-center-ax-api.md) for the element
and the probe evidence.

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
closing the panel on the way out. **Out of scope** (open seeds): selecting a notification and moving
that selection, per-notification action menus, `clear-all` / `clear-all-for-app`, reacting to
notifications arriving while the mode is active, and which application regains focus once the
overlay closes.

## Conventions

Honors AX-only (C-1), permission required (C-2), OS resilience (C-3), macOS-only (C-4),
version-selectable access behind a seam (C-5), and all cross-cutting requirements (X-1..X-4) — with
X-2 read as stated there: interactive mode communicates through its overlay, not stdout.
