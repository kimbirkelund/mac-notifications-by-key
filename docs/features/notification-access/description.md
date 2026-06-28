# Notification access — Description

**Notification access** turns the macOS Notification Center's Accessibility surface into a small set
of scriptable operations. macOS exposes no public API to read or act on another app's notifications;
the only robust handle is the AX tree of the Notification Center process, where each presented
notification is an element with readable title/subtitle/body and a set of named actions
([definitions](../../definitions.md)).

## The operations

- **list** — enumerate the currently-presented notifications, newest first, each with its app,
  title, subtitle, body, available action names, and a 0-based index. Output is JSON
  ([X-2](../../cross-cutting.md)).
- **dismiss `<index>`** — dismiss the notification at that index.
- **action `<index> <name>`** — perform the named action (e.g. `Show`, `Show Details`, or an
  app-specific action) on that notification.
- **press `<index>`** — perform the default activation (open the notification / launch its app).
- **doctor** — report whether Accessibility trust is granted and how to grant it
  ([C-2](../../constraints.md)).

## Mental model

```
nbk list ──► [ {index:0, app, title, subtitle, body, actions:[…]}, … ]  (JSON, newest first)
                       │
        choose an index n from that list
                       ▼
nbk dismiss n   nbk action n "Show"   nbk press n
```

`list` is the read half; `dismiss`/`action`/`press` are the act half. A typical hotkey binding runs
one act command against index `0` (the newest notification).

## Two mechanism facts that shape the design (probe-verified, macOS 26.5.1)

- **Render delay & transient window.** The AX window exposing notifications exists only while a
  banner is on screen or the panel is open, and a banner takes a short interval to appear after
  delivery. Read/act operations therefore **poll** for the target up to a bounded `--wait` timeout
  before concluding "none present" ([C-3](../../constraints.md)).
- **Focus-before-close.** Performing the `Close` action without first focusing the element returns
  success but is a no-op. Dismissal must set the element focused, let it settle briefly, then
  perform `Close`. This quirk is internal to the AX adapter; it is not visible at the CLI.

## Scope

In scope: reading presented notifications and acting on a single designated one by index. **Out of
scope** (open seeds): a long-running daemon/watch mode, selecting by app/content rather than index,
replying inline, and reading the historical notification list from the persistent panel beyond what
is currently presented.

## Conventions

Honors AX-only (C-1), permission required (C-2), OS resilience (C-3), CLI-only (C-4), macOS-only
(C-5), and all cross-cutting requirements (X-1..X-4).
