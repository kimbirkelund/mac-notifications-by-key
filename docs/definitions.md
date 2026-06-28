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
  — operations must account for this (see [C-3](constraints.md), `RNA-*` wait behavior).
- **Notification Center.** The macOS process (`com.apple.notificationcenterui`) that owns the banner
  and the persistent notification list. It is the target of all AX reads and actions. There is **no
  public API to read or act on another app's notifications**; the AX surface of this process is the
  only mechanism.
- **Action.** A named operation a notification exposes, surfaced as an AX action on its element —
  e.g. `Close`, `Show`, `Show Details`, the default activate (`AXPress`), and app-specific actions.
  Acting on a notification means performing one of these (some require focusing the element first;
  see [notification-access](features/notification-access/_index.md)).
- **Selector.** How a CLI invocation designates which notification to act on (e.g. an index into the
  current list, newest-first). Selection logic is pure and unit-tested independently of the AX layer
  (see [testing](testing.md)).
