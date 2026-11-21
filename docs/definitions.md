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
  current list, top to bottom). Selection logic is pure and unit-tested independently of the AX
  layer (see [testing](testing.md)).
- **Demo file.** A JSON file given to `demo-nc`, the demo application, listing the notifications
  that it presents in its list (closed at launch unless `demo-nc` is started with `--open`; its menu
  bar item opens and closes it) and that [interactive mode](features/interactive-mode/_index.md)
  shows instead of Notification Center's when invoked with `--demo`, newest first. Each notification
  has an `app` (a notification or stack member without one is rejected) and may have a `title`, a
  `subtitle`, a `body`, an `activateCloses` flag (default true) saying whether activating it removes
  it, and `actions` (default none), and may schedule its `arrivesAfter` (it is absent from the list
  until that many seconds after the demo application starts, whether or not the list is open) and
  its `leavesAfter` (it is removed after that many seconds). Instead of, or as well as, a number of
  seconds, its arrival or departure may wait for a signal: `arrivesOn` or `leavesOn` set to
  `"signal"` keeps it absent, or present, until the demo application receives `SIGUSR2`, which makes
  every such pending arrival and departure happen at once. A notification with both a delay and
  `arrivesOn` arrives once both have passed; one with both `leavesAfter` and `leavesOn` leaves at
  whichever comes first. It may also give a `takes` delay, the seconds after an entry that removes
  it is performed before it leaves; the entry itself returns at once. An action is either a bare
  name, which removes the notification when performed, or an object with a `name`, a `closes` flag,
  a `field` flag (default false) and a `fails` flag (default false). Performing a `field` action
  opens an editable reply field on the notification, exposed through AX as a text field, and keeps
  the notification; Return in the field removes the notification, after any `takes` delay, whatever
  `closes` says, and Escape drops the field and keeps the notification. Performing a `fails` action
  makes the demo application report the action to the Accessibility API as failed; the action's
  effect follows shortly after. A notification with a non-empty `members` array (each member a
  notification of the same shape, newest first) is a collapsed stack presented under its own `app`
  and `title`: expanding it replaces it with its members, dismissing it removes it with its members,
  and it cannot be activated. Members cannot themselves have `members`, nor `arrivesAfter`,
  `leavesAfter`, `arrivesOn` or `leavesOn`; `arrivesAfter` and `leavesAfter` are non-negative
  numbers of seconds, and `"signal"` is the only value `arrivesOn` and `leavesOn` accept. Unknown
  keys are ignored. A file that is missing, unreadable or not valid is reported by `demo-nc` on
  standard error with a non-zero exit status, before any window appears.
- **Demo state.** What the demo application presents at a moment, as a JSON object with two keys:
  `notifications`, the list of presented notifications in list order, and `listOpen`, whether its
  list is open. Each notification has an `id` that stays the same while it is presented (an expanded
  stack's members get ids of their own), its `app`, `title`, `subtitle` and `body` (left out when it
  has none), `actions`, the list of its action names, `collapsedStack`, whether it is a collapsed
  stack, `hiddenMembers`, how many members a collapsed stack hides (0 otherwise), and `replyField`,
  whether its reply field is shown. Notifications that have not yet arrived or have already left are
  not part of it.
- **Demo event.** A report from the demo application that something happened, written to standard
  output as one JSON object per line. Every event has a `seq`, a number that starts at 1 and grows
  by one with each event, an `event` name and the full demo state, under `state`, as it is right
  after the event. An event is written only once the demo application's window shows that state, so
  a reader that has seen it may rely on what the window exposes. The event names are `ready` (once,
  when the window and menu bar item exist), `arrived` and `departed` (a notification became
  presented or stopped being presented because of its schedule or a `SIGUSR2`, with its `id`),
  `list-opened` and `list-closed`, and `action`. An `action` event says what was done to a
  notification and with what result: its `kind` is `press`, `close`, `named`, `expand`, `clear-all`
  or `submit-field`, with the target `id` when there is one, the `action` name for `named`, the
  typed `text` for `submit-field`, and an `outcome` of `applied` (it took effect), `kept` (it was
  performed and the notification stayed) or `failed` (it was refused, with the reason in `error`). A
  failed action changes nothing, and the event is still written. The event stream is for the harness
  and tests that start the demo application; `nbk` never reads it.
