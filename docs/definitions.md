# Definitions

Shared domain vocabulary used across all features.

- **Notification.** A single message presented by macOS on behalf of an application: a **title**,
  optional **subtitle**, optional **body**, the originating **app**, and a set of **actions**. The
  system reads these from the Notification Center process via the Accessibility API (see
  [C-1](constraints.md)). Each notification carries an opaque per-element **identifier** (a UUID)
  that is stable only for the lifetime of that presented element.
- **Banner.** A notification while it is transiently presented on screen (top-right). The
  Accessibility window that exposes notifications exists **only while a banner is on screen or the
  Notification Center panel is open**, and a banner takes a short interval to render after delivery
  — operations must account for this (see [C-3](constraints.md), `RNA-*` wait behavior). The panel
  half of that condition can be forced: pressing the menu bar clock over AX opens the panel on
  demand (see the [AX reference](notification-center-ax-api.md)), which is how
  [interactive mode](features/interactive-mode/_index.md) guarantees itself a subject.
- **Notification Center.** The macOS process (`com.apple.notificationcenterui`) that owns the banner
  and the persistent notification list. It is the target of all AX reads and actions. There is **no
  public API to read or act on another app's notifications**; the AX surface of this process is the
  only mechanism.
- **Action.** A named operation a notification exposes, surfaced as an AX action on its element —
  e.g. `Close`, `Show`, `Show Details`, the default activate (`AXPress`), and app-specific actions.
  Acting on a notification means performing one of these (some require focusing the element first;
  see [notification-access](features/notification-access/_index.md)).
- **Action panel.** In [interactive mode](features/interactive-mode/_index.md), the small panel the
  overlay draws to the left of the **selected** notification, listing what can be done to it:
  `Activate` (or `Expand` for a collapsed stack), `Dismiss`, and the notification's named actions,
  each with its **activator** — the single key that triggers that entry. Only the selected
  notification has one.
- **Selector.** How a CLI invocation designates which notification to act on (e.g. an index into the
  current list, newest-first). Selection logic is pure and unit-tested independently of the AX layer
  (see [testing](testing.md)).
- **Demo file.** A JSON file given to `demo-nc`, the demo application, listing the notifications
  that it presents in its list (closed at launch unless `demo-nc` is started with `--open`; its menu
  bar item opens and closes it) and that [interactive mode](features/interactive-mode/_index.md)
  shows instead of Notification Center's when invoked with `--demo`, newest first. Each notification
  has an `app` (a notification or stack member without one is rejected) and may have a `title`, a
  `subtitle`, a `body`, an `activateCloses` flag (default true) saying whether activating it removes
  it, and `actions` (default none), and may schedule its `arrivesAfter` (it is absent from the list
  until that many seconds after the demo application starts, whether or not the list is open) and
  its `leavesAfter` (it is removed after that many seconds), and may give a `takes` delay, the
  seconds after an entry that removes it is performed before it leaves; the entry itself returns at
  once. An action is either a bare name, which removes the notification when performed, or an object
  with a `name`, a `closes` flag and a `field` flag (default false). Performing a `field` action
  opens an editable reply field on the notification, exposed through AX as a text field, and keeps
  the notification; Return in the field removes the notification, after any `takes` delay, whatever
  `closes` says, and Escape drops the field and keeps the notification. A notification with a
  non-empty `members` array (each member a notification of the same shape, newest first) is a
  collapsed stack presented under its own `app` and `title`: expanding it replaces it with its
  members, dismissing it removes it with its members, and it cannot be activated. Members cannot
  themselves have `members`, nor `arrivesAfter` or `leavesAfter`; both are non-negative numbers of
  seconds. Unknown keys are ignored. A file that is missing, unreadable or not valid is reported by
  `demo-nc` on standard error with a non-zero exit status, before any window appears.
