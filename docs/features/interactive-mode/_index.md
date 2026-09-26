# Interactive mode

Feature code: **`IM`** (requirement IDs `RIM-*`; see [conventions](../../conventions.md)).

**Interactive mode** is a long-running mode, entered by one CLI invocation, in which the system
renders a graphical overlay alongside the macOS Notification Center UI — to pick a notification, see
the actions it exposes, and invoke cross-cutting actions (clear-all, clear-all-for-app). The overlay
never reimplements Notification Center's presentation of notifications; it sits _beside_ and _above_
it. Only the first step is specified so far: the overlay that signals the mode is active.

- [Description](description.md) — how it works (prose, mental model).
- [Requirements](requirements.md) — behavioral requirements (`RIM-*`) and open seeds; selection,
  per-notification action menus, and clear-all are still seeds.
- [Acceptance scenarios](acceptance/_index.md) — BDD scenarios for the overlay signal; the notes
  there record what the harness adds to drive a long-running, focus-taking process.
