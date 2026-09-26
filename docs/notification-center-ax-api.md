# Notification Center — Accessibility API reference

A developer's guide to what the macOS Notification Center process (`com.apple.notificationcenterui`)
exposes over the public Accessibility (AX) API, and what `nbk` reads and drives through it. Written
to support building richer integrations (custom UI, richer selection, stack handling) on top of the
same surface.

> **Grounding.** Concrete shapes (roles, identifiers, action names) are probe-verified on **macOS
> 26.5.1** and are **undocumented and version-sensitive** ([C-3](constraints.md)) — Apple changed
> this tree across Big Sur, Sequoia, and Tahoe. Anything marked _standard AX_ is a general
> capability of the Accessibility API that `nbk` does **not** currently exercise; treat it as
> "should work, not yet probed here".

This is a capability reference, not an implementation map. It describes the AX surface and which
parts `nbk` relies on — for how `nbk` is put together, read the code.

---

## 1. Prerequisites

### Accessibility trust

Every AX read/act requires the **calling process** to hold Accessibility trust.

- `AXIsProcessTrusted()` is the whole gate. Without trust every `AXUIElementCopy*` /
  `*PerformAction` returns failure or empty; there is no partial mode.
- Trust is per-_host_ (the terminal, `skhd`, etc.), not per-user.
- There is **no** programmatic API to grant or revoke trust — only System Settings → Privacy &
  Security → Accessibility.

`nbk` checks trust before every operation and reports its absence actionably rather than returning
empty results ([C-2](constraints.md)).

### Locating the process

Notification Center is a normal running app: resolve its pid, then make an application-level AX
element with `AXUIElementCreateApplication(pid)` as the root handle for everything below. `nbk`
resolves the pid by bundle identifier (`com.apple.notificationcenterui`), falling back to a scan of
the process table for an executable under `CoreServices/NotificationCenter.app/` — the bundle-id
lookup occasionally comes back empty in non-GUI process contexts.

> **Never hardcode the pid or a child index** ([C-3](constraints.md)). Resolve the pid every call
> and locate elements structurally.

### Opening the panel (the menu bar clock)

The notification window only exists while a banner is up or the panel is open (§2) — but the panel
can be **opened programmatically over AX**, so that state need not be waited for. The toggle is the
menu bar clock, which does **not** belong to Notification Center. Which process owns it depends on
the macOS release. Both trees are probe-verified on the release they are labelled with:

```
macOS 27 — Application (com.apple.MenuBarAgent)
└─ AXExtrasMenuBar
   └─ AXGroup
      └─ AXMenuBarItem  subrole=AXMenuExtra
           identifier = "com.apple.menuextra.clock"
           description = "Clock"

macOS 26 — Application (com.apple.controlcenter)
└─ AXExtrasMenuBar                       ← NOTE: kAXMenuBarAttribute is absent on this app
   └─ AXMenuBarItem  subrole=AXMenuExtra
        identifier = "com.apple.menuextra.clock"
        description = "Clock"
        actions    = ["AXPress", "AXCancel"]
```

On macOS 27 ControlCenter's `AXExtrasMenuBar` returns no value, so look under MenuBarAgent first and
fall back to ControlCenter. Search the extras bar's descendants rather than its direct children,
since macOS 27 adds the `AXGroup` level.

`AXPress` on that element opens the panel; pressing it again closes it. Probe-verified on **macOS
26.5.2 (25F84)**. Bullets tagged _(also 27.0)_ were re-checked on **macOS 27.0**; the rest are
verified on 26 only:

- **The window appears on demand** _(also 27.0)_. `windows=0` before the press, `windows=1` after —
  as `AXWindow` titled `"Notification Center"`, subrole `AXSystemDialog`. This is what makes the
  panel-only surface (per-app clear, `Clear All`, the persistent list) reachable at all.
- **Opening it does not steal focus.** The frontmost application is unchanged across the press.
- **The panel is sticky.** It is _not_ dismissed by another application taking focus, nor by that
  application quitting. Whatever opens it owns closing it.
- **The panel window sits at window level 21** _(also 27.0)_. Measured on the on-screen window list:
  an overlay at level 25 or above (`statusBar`, `popUpMenu`, `screenSaver`) draws in front of the
  panel; at level 3 or 0 (`floating`, `normal`) the panel draws in front. Relevant to anything that
  wants to paint over or under it. The menu bar and Control Centre's own windows are at level 25,
  i.e. above the panel.
- Sibling extras are addressable the same way (`com.apple.menuextra.battery`, `.bluetooth`, `.wifi`,
  `.controlcenter`, `.now-playing`), several with an empty identifier and description.

> The identifier is an undocumented Apple string like everything else here ([C-3](constraints.md)).
> Match on it, but fall back to subrole `AXMenuExtra` plus description rather than failing hard.

### Telling whether the panel is open

The press is a toggle, so pressing without knowing the current state can open a panel that was meant
to close and leave it stranded. Read the state first and press only when it differs.

Everything in this subsection is verified on **macOS 27.0 only**; it has not been checked on
macOS 26.

Neither the window's subrole nor its size tells the panel apart from a banner. On macOS 27 a banner
window is also an `AXWindow` of subrole `AXSystemDialog`, sized to the full screen, and it sits at
the same window level. What only the panel has is its **"Edit Widgets" button**: an `AXButton` with
identifier `widget-editor-button`, a few levels below the window:

```
AXWindow  subrole=AXSystemDialog
└─ AXGroup
   └─ AXGroup
      └─ AXScrollArea
         └─ AXButton  identifier="widget-editor-button"  description="Edit Widgets"
```

> The panel is open when Notification Center has an `AXSystemDialog` window with a descendant
> `AXButton` whose identifier is `widget-editor-button`.

Search for the button at any depth rather than along the exact path above. A panel mid-close can
still read as open for a moment, so let the reading settle before acting on it.

### Where access lives in `nbk`

Notification Center interaction sits behind the `NotificationCenterAccess` protocol, obtained from
`NotificationCenterAccessFactory` ([C-5](constraints.md)). Callers depend only on the protocol; the
factory selects the implementation, so a future macOS layout is an added implementation plus a
factory branch, not a change rippling through callers. One implementation exists today.

---

## 2. The element tree

The AX window only exists **while a banner is on screen or the panel is open**. With nothing
presented there are no notification windows — a clean, non-error "empty" state. The panel half of
that condition is controllable: press the menu bar clock extra (§1) to bring the window into
existence on demand.

Verified shape (macOS 26.5.1):

```
Application (com.apple.notificationcenterui)
└─ AXWindow  "Notification Center"          ← kAXWindowsAttribute on the app
   └─ AXGroup
      └─ AXGroup
         └─ AXScrollArea
            └─ AXGroup   ← a NOTIFICATION: an AXGroup that exposes an AXPress action
               ├─ AXStaticText  identifier="title"     value=<title text>
               ├─ AXStaticText  identifier="subtitle"  value=<subtitle text>
               └─ AXStaticText  identifier="body"      value=<body text>
```

### How notifications are found

The exact depth above is not relied on. Instead the walk descends every window depth-first and
matches a notification **structurally**:

> A notification element = **role `AXGroup`** _and_ its action list **contains `AXPress`**.

This is deliberately loose so it survives the tree being reshuffled between OS versions. Matches
come back in the tree's natural order, surfaced to the CLI as index `0..n` ("newest first").

### AX primitives `nbk` uses

| Call                            | Purpose                                      |
| ------------------------------- | -------------------------------------------- |
| `AXUIElementCreateApplication`  | root app element from the pid                |
| `AXUIElementCopyAttributeValue` | read any attribute                           |
| `AXUIElementCopyActionNames`    | list an element's actions                    |
| `AXUIElementPerformAction`      | fire an action (`AXPress`, `Close`, …)       |
| `AXUIElementSetAttributeValue`  | set focus (see the focus-before-close quirk) |

### Attributes read

| Attribute                 | On element         | Meaning                                                 |
| ------------------------- | ------------------ | ------------------------------------------------------- |
| `kAXWindowsAttribute`     | app                | top-level windows                                       |
| `kAXChildrenAttribute`    | any                | child elements                                          |
| `kAXRoleAttribute`        | any                | e.g. `AXGroup`, `AXStaticText`                          |
| `kAXIdentifierAttribute`  | static text        | `"title"` / `"subtitle"` / `"body"`                     |
| `kAXValueAttribute`       | static text        | the actual text content                                 |
| `kAXDescriptionAttribute` | notification group | `"App, Title, Subtitle, Body"` — first field = app name |
| `kAXFocusedAttribute`     | notification group | set to focus before Close                               |

### Roles matched

`kAXGroupRole` (`AXGroup`) — the window subtree and the notification itself; `kAXStaticTextRole`
(`AXStaticText`) — the text fields.

---

## 3. Reading a notification

Each notification maps to a value with `app`, `title`, `subtitle`, `body`, its available action
names, and a 0-based index:

- **title / subtitle / body** — the group's `AXStaticText` children, keyed by
  `kAXIdentifierAttribute`, value taken from `kAXValueAttribute`.
- **app** — the first comma-field of the group's `kAXDescriptionAttribute`.
- **actions** — the element's action names, minus `AXPress` (see §4).

### Banner render delay (quirk: poll-for-render)

A delivered banner takes **~1 s** to appear in the tree, so reads poll (short interval, bounded by a
caller-supplied wait) until an element appears or the deadline passes. Any integration reading right
after delivery must poll — a single immediate read will miss fresh banners.

---

## 4. Actions

Notification Center surfaces actions as **opaque descriptor strings**, not clean names:

```
Name:Close\nTarget:0x0\nSelector:(null)
```

The display name is parsed out of the `Name:` field, and mapped back to the raw descriptor to
perform it. To act: enumerate an element's actions with `AXUIElementCopyActionNames`, resolve
display → raw, then `AXUIElementPerformAction`.

Verified actions on a notification group (macOS 26.5.1):

| Display name   | Meaning                                                                                                                 |
| -------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `AXPress`      | default activation — click the notification (open it). Exposed as `press`. Filtered out of the user-facing action list. |
| `Close`        | dismiss the notification. Backs `dismiss` (with the focus quirk below).                                                 |
| `Show`         | expand / reveal                                                                                                         |
| `Show Details` | app-specific detail action (seen on e.g. Script Editor)                                                                 |

App-defined custom action buttons (the ones added to a `UNNotificationCategory`) also appear here as
additional named actions — the set is per-notification, so always enumerate rather than assume.

### Focus-before-close (quirk)

`Close` **silently no-ops** unless the element is focused first. `dismiss` therefore:

1. sets `kAXFocusedAttribute` true on the element,
2. settles briefly,
3. performs `Close`,
4. polls (bounded) until the element leaves the tree — `Close` is async and returns before the
   banner actually disappears.

---

## 5. Stacks / grouped notifications

macOS groups multiple notifications from one app into a **stack** (a collapsed pile you click to
expand). What this means for the AX surface:

- **What `nbk` does today:** nothing stack-aware. The tree is flattened, returning _every_
  `AXGroup`-with-`AXPress` in tree order. When a stack is **expanded** each member is a separate
  matched element with its own index. When **collapsed**, typically only the front notification is a
  live element — members behind it are not addressable until expanded.
- **The stack container itself** is a parent `AXGroup` wrapping the member groups. It is _not_
  matched as a notification unless it happens to expose `AXPress`. This is the natural place to hang
  stack-level operations, and is worth probing before building stack UI:
  - Enumerate its `kAXChildrenAttribute` to get members.
  - Look for a `Show`/`Expand`-style action on the container (_standard AX_ — verify the exact
    name).
  - `kAXDescriptionAttribute` on the container often carries a count / "App, N notifications"
    summary.
- **"Clear All" / per-app clear** buttons appear when the panel is open — as `AXButton` elements
  (see §6). These are the fastest path to bulk dismissal but are **not** wired up today.

> To build stack features: open the panel, dump the container subtree once, and pin down (a) the
> container role, (b) its expand action name, (c) whether collapsed members are present-but-hidden
> or absent. Do it behind the structural-matching discipline of [C-3](constraints.md).

---

## 6. UI element / geometry information

The AX API is not just text — it exposes layout, so an integration _can_ know where and how big each
popup is. **None of the following is used by `nbk` today**; all are _standard AX_ and should be
probed before you depend on them.

| Attribute                                              | Type                 | Use                                                             |
| ------------------------------------------------------ | -------------------- | --------------------------------------------------------------- |
| `kAXPositionAttribute`                                 | `AXValue`(`CGPoint`) | screen position of the notification / button                    |
| `kAXSizeAttribute`                                     | `AXValue`(`CGSize`)  | on-screen size                                                  |
| `kAXFrameAttribute`                                    | `AXValue`(`CGRect`)  | combined rect (when present)                                    |
| `kAXSubroleAttribute`                                  | String               | finer classification (e.g. `AXCloseButton`, `AXStandardWindow`) |
| `kAXEnabledAttribute`                                  | Bool                 | whether an action/button is currently actionable                |
| `kAXHelpAttribute`                                     | String               | tooltip/help text                                               |
| `kAXParentAttribute` / `kAXTopLevelUIElementAttribute` | element              | walk upward (e.g. member → stack container)                     |

Discovery helpers worth using while probing:

- `AXUIElementCopyAttributeNames` — **every** attribute an element actually exposes. The single most
  useful call for reverse-engineering a new OS layout; unused by `nbk`, but it's how you'd map an
  unfamiliar tree.
- `AXUIElementCopyParameterizedAttributeNames` — parameterized attributes, if any.

### Buttons in the tree

When the Notification Center **panel** (not just a banner) is open, interactive controls surface as
`AXButton` elements — action buttons, `Close`, `Options`/chevrons, and panel-level `Clear`.
Enumerate them structurally (role `AXButton`, disambiguate by `kAXSubroleAttribute` /
`kAXTitleAttribute` / `kAXDescriptionAttribute`) rather than by index. Coordinates from
`kAXPosition` / `kAXSize` let you correlate an AX element with a pixel region if you ever need to
overlay custom UI — without resorting to OCR or blind clicks (which [C-1](constraints.md) forbids
anyway).

---

## 7. Live change notifications (AXObserver)

`nbk` is a one-shot CLI, so it **polls** (§3, §4). For a long-running integration that wants to
react to notifications arriving/leaving, the AX API offers push instead of poll (_standard AX,
unused here_):

- `AXObserverCreate(pid, callback, &observer)`
- `AXObserverAddNotification(observer, element, kAXCreatedNotification / kAXUIElementDestroyedNotification / kAXFocusedUIElementChangedNotification, ctx)`
- add the observer's run-loop source to your run loop.

This removes the render-delay polling entirely for a resident process and is the recommended
foundation for any "custom UI that mirrors Notification Center live" work.

---

## 8. Gotchas & interesting notes

- **The window is ephemeral, but not out of reach.** No banner/panel ⇒ no window ⇒ empty result,
  _not_ an error. Don't treat empty as failure — and where a window is actually needed, open the
  panel via the menu bar clock extra (§1) instead of waiting for one.
- **The panel outlives whoever opened it.** Focus changes don't close it and neither does the
  opening process exiting. Anything that opens the panel must close it again.
- **Everything is version-sensitive.** Roles, identifiers, the `"App, Title, Subtitle, Body"`
  description format, and even action names can change between macOS releases. Match structurally;
  degrade to "layout not recognized" rather than crashing ([C-3](constraints.md)).
- **Actions are opaque descriptors**, not names — you must parse `Name:` out and keep the raw string
  to perform it. Don't build the descriptor yourself; enumerate and match.
- **`AXPress` is always present** on a notification (it's the very definition of one) and is the
  "default activation". It is deliberately hidden from the user-facing action list.
- **Two behaviors need a settle/poll**, both timing-related and both fragile to tune: focus → Close,
  and the post-Close disappearance wait.
- **Identifiers are the reliable text key**, not child order. Key title/subtitle/body off
  `kAXIdentifierAttribute`; positions of the static-text children are not guaranteed.

---

## 9. Quick reference — used vs. available

**Used by `nbk` today:** `AXIsProcessTrusted`, `AXUIElementCreateApplication`,
`AXUIElementCopyAttributeValue`, `AXUIElementCopyActionNames`, `AXUIElementPerformAction`,
`AXUIElementSetAttributeValue`; attributes `Windows`, `Children`, `Role`, `Identifier`, `Value`,
`Description`, `Focused`, `Subrole`; roles `AXGroup`, `AXStaticText`, `AXButton` (the panel's "Edit
Widgets" button, to tell the panel from a banner); actions `AXPress`, `Close`, `Show`,
`Show Details`; the menu bar clock extra for opening and closing the panel (§1).

**Available but unused (probe before relying):** `AXUIElementCopyAttributeNames`, `AXObserver*`
(live events); attributes `Position`, `Size`, `Frame`, `Enabled`, `Help`, `Parent`,
`TopLevelUIElement`; action buttons as `AXButton`; stack-container children/expand action and
panel-level `Clear All`.
