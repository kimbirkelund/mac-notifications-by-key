# Notification Center — Accessibility API reference

A developer's guide to what the macOS Notification Center process (`com.apple.notificationcenterui`)
exposes over the public Accessibility (AX) API, and how `nbk` reads and drives it. Written to
support building richer integrations (custom UI, richer selection, stack handling) on top of the
same surface.

> **Grounding.** Every "we use this" claim is cited to
> `Sources/NotificationAX/NotificationAX.swift`. Concrete shapes (roles, identifiers, action names)
> are probe-verified on **macOS 26.5.1** (see [`constraints.md`](constraints.md) C-3) and are
> **undocumented and version-sensitive** — Apple changed this tree across Big Sur, Sequoia, and
> Tahoe. Anything marked _standard AX_ is a general capability of the Accessibility API that we do
> **not** currently exercise here; treat it as "should work, not yet probed in this repo".

---

## 1. Prerequisites

### Accessibility trust

Every AX read/act requires the **calling process** to hold Accessibility trust.

- `AXIsProcessTrusted() -> Bool` — the whole gate. No trust ⇒ every `AXUIElementCopy*`/`Perform*`
  returns failure/empty; there is no partial mode.
- Trust is per-_host_ (the terminal, `skhd`, etc.), not per-user.
- There is **no** programmatic API to grant or revoke trust — only System Settings → Privacy &
  Security → Accessibility.

`NotificationAX.isTrusted` (`NotificationAX.swift:54`) wraps it; `requirePID()` (`:140`) checks it
before any operation.

### Locating the process

Notification Center is a normal running app; find its pid, then make an app-level AX element.

- Primary:
  `NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")`
  → `.processIdentifier` (`:56–64`).
- Fallback: scan the BSD process table (`proc_listpids` / `proc_pidpath`) for an executable path
  containing `CoreServices/NotificationCenter.app/` (`:71–92`). Needed because
  `NSRunningApplication`'s snapshot is occasionally empty in non-GUI/test hosts.
- `AXUIElementCreateApplication(pid) -> AXUIElement` is the root handle for everything below
  (`:171`).

> **Never hardcode the pid or a child index** (C-3). Resolve the pid every call; locate elements
> structurally.

---

## 2. The element tree

The AX window only exists **while a banner is on screen or the panel is open**. With nothing
presented there are no notification windows — a clean, non-error "empty" state.

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

### How we find notifications

We do **not** rely on the exact depth above. Instead we walk every window depth-first and match a
notification structurally (`notificationElements`, `:170–186`):

> A notification element = **role is `AXGroup`** _and_ its action list **contains `AXPress`**.

This is deliberately loose so it survives the tree reshuffling between OS versions. Order of the
returned array is the tree's natural order, surfaced to the CLI as index `0..n` ("newest first").

### AX primitives we use (all of `NotificationAX.swift`)

| Call                                | Purpose                                            | Site           |
| ----------------------------------- | -------------------------------------------------- | -------------- |
| `AXUIElementCreateApplication(pid)` | root app element                                   | `:171`         |
| `AXUIElementCopyAttributeValue`     | read any attribute (wrapped by `attr`)             | `:216–219`     |
| `AXUIElementCopyActionNames`        | list an element's actions (wrapped by `axActions`) | `:222–226`     |
| `AXUIElementPerformAction`          | fire an action (`AXPress`, `Close`, …)             | `:129`, `:163` |
| `AXUIElementSetAttributeValue`      | set focus (see quirks)                             | `:112`         |

### Attributes we read

| Constant / literal        | On element         | Meaning                                                 | Site   |
| ------------------------- | ------------------ | ------------------------------------------------------- | ------ |
| `kAXWindowsAttribute`     | app                | top-level windows                                       | `:172` |
| `kAXChildrenAttribute`    | any                | child elements                                          | `:229` |
| `kAXRoleAttribute`        | any                | e.g. `AXGroup`, `AXStaticText`                          | `:233` |
| `kAXIdentifierAttribute`  | static text        | `"title"` / `"subtitle"` / `"body"`                     | `:193` |
| `kAXValueAttribute`       | static text        | the actual text content                                 | `:194` |
| `kAXDescriptionAttribute` | notification group | `"App, Title, Subtitle, Body"` — first field = app name | `:203` |
| `kAXFocusedAttribute`     | notification group | set to focus before Close                               | `:112` |

### Roles we match

`kAXGroupRole` (`AXGroup`) — window subtree and the notification itself (`:178`, `:192`) ·
`kAXStaticTextRole` (`AXStaticText`) — the text fields (`:192`).

---

## 3. Reading a notification

`item(from:index:)` (`:188–212`) produces the CLI's
[`NotificationItem`](../Sources/NotificationCore/NotificationItem.swift):

- **title / subtitle / body** — iterate the group's `AXStaticText` children, key on
  `kAXIdentifierAttribute`, take `kAXValueAttribute`.
- **app** — first comma-field of the group's `kAXDescriptionAttribute`.
- **actions** — action names minus `AXPress` (see §4).

### Banner render delay (quirk: poll-for-render)

A delivered banner takes **~1 s** to appear in the tree. `read(wait:)` (`:96–105`) polls every **0.2
s** until an element appears or the `--wait` deadline passes. Any integration reading right after
delivery must poll — a single immediate read will miss fresh banners.

---

## 4. Actions

Notification Center surfaces actions as **opaque descriptor strings**, not clean names:

```
Name:Close\nTarget:0x0\nSelector:(null)
```

[`ActionName`](../Sources/NotificationCore/NotificationItem.swift#L89) parses the display name out
of `Name:...` and maps a display name back to the raw descriptor to perform it.

- **List** an element's actions: `AXUIElementCopyActionNames` (`:222`).
- **Perform**: resolve display→raw, then `AXUIElementPerformAction(element, raw)` (`:155–166`).

Verified actions on a notification group (macOS 26.5.1):

| Display name   | Meaning                                                                                                                 |
| -------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `AXPress`      | default activation — click the notification (open it). Exposed as `press`. Filtered out of the user-facing action list. |
| `Close`        | dismiss the notification. Backs `dismiss` (with the focus quirk below).                                                 |
| `Show`         | expand / reveal                                                                                                         |
| `Show Details` | app-specific detail action (seen on e.g. Script Editor)                                                                 |

App-defined custom action buttons (the ones you add to a `UNNotificationCategory`) also appear here
as additional named actions — the set is per-notification, so always enumerate rather than assume.

### Focus-before-close (quirk)

`Close` **silently no-ops** unless the element is focused first. `dismiss` (`:109–125`):

1. `AXUIElementSetAttributeValue(el, kAXFocusedAttribute, kCFBooleanTrue)`,
2. sleep 0.3 s to settle,
3. perform `Close`,
4. poll (≤2 s) until the element leaves the tree — `Close` is async and returns before the banner
   actually disappears.

---

## 5. Stacks / grouped notifications

macOS groups multiple notifications from one app into a **stack** (a collapsed pile you click to
expand). What this means for the AX surface:

- **What `nbk` does today:** nothing stack-aware. `notificationElements` flattens the whole tree and
  returns _every_ `AXGroup`-with-`AXPress` it finds, in tree order. When a stack is **expanded**
  each member is a separate matched element and appears as its own index. When **collapsed**,
  typically only the front notification is a live element in the tree — members behind it are not
  addressable until expanded.
- **The stack container itself** is a parent `AXGroup` wrapping the member groups. It is _not_
  matched as a notification unless it happens to expose `AXPress`. This is the natural place to hang
  stack-level operations, and is worth probing before building stack UI:
  - Enumerate its `kAXChildrenAttribute` to get members.
  - Look for a `Show/Expand`-style action on the container (_standard AX_ — verify the exact name).
  - `kAXDescriptionAttribute` on the container often carries a count / "App, N notifications"
    summary.
- **"Clear All" / per-app clear** buttons appear when the panel is open — as `AXButton` elements
  (see §6). These are the fastest path to bulk dismissal but are **not** wired up today.

> To build stack features: open the panel, dump the container subtree once, and pin down (a) the
> container role, (b) its expand action name, (c) whether collapsed members are present-but-hidden
> or absent. Do it behind the structural-matching discipline of C-3.

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

- `AXUIElementCopyAttributeNames(el, &names)` — **every** attribute an element actually exposes.
  This is the single most useful call for reverse-engineering a new OS layout; `nbk` doesn't call it
  but it's how you'd map an unfamiliar tree.
- `AXUIElementCopyParameterizedAttributeNames` — parameterized attributes, if any.

### Buttons in the tree

When the Notification Center **panel** (not just a banner) is open, interactive controls surface as
`AXButton` elements — action buttons, `Close`, `Options`/chevrons, and panel-level `Clear`.
Enumerate them structurally (role `AXButton`, disambiguate by `kAXSubroleAttribute` /
`kAXTitleAttribute` / `kAXDescriptionAttribute`) rather than by index. Coordinates from
`kAXPosition`/`kAXSize` let you correlate an AX element with a pixel region if you ever need to
overlay custom UI — without resorting to OCR or blind clicks (which C-1 forbids anyway).

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

- **The window is ephemeral.** No banner/panel ⇒ no window ⇒ empty result, _not_ an error. Don't
  treat empty as failure.
- **Everything is version-sensitive.** Roles, identifiers, the `"App, Title, Subtitle, Body"`
  description format, and even action names can change between macOS releases. Match structurally;
  degrade to "layout not recognized" rather than crashing (C-3).
- **Actions are opaque descriptors**, not names — you must parse `Name:` out and keep the raw string
  to perform it. Don't build the descriptor yourself; enumerate and match.
- **`AXPress` is always present** on a notification (it's our very definition of one) and is the
  "default activation". It is deliberately hidden from the user-facing action list.
- **Two behaviors need a settle/poll**, both timing-related and both fragile to tune: focus→0.3 s→
  Close, and the ≤2 s post-Close disappearance wait.
- **Identifiers are the reliable text key**, not child order. Key title/subtitle/body off
  `kAXIdentifierAttribute`; positions of the static-text children are not guaranteed.

---

## 9. Quick reference — used vs. available

**Used by `nbk` today:** `AXIsProcessTrusted`, `AXUIElementCreateApplication`,
`AXUIElementCopyAttributeValue`, `AXUIElementCopyActionNames`, `AXUIElementPerformAction`,
`AXUIElementSetAttributeValue`; attributes `Windows`, `Children`, `Role`, `Identifier`, `Value`,
`Description`, `Focused`; roles `AXGroup`, `AXStaticText`; actions `AXPress`, `Close`, `Show`,
`Show Details`.

**Available but unused (probe before relying):** `AXUIElementCopyAttributeNames`, `AXObserver*`
(live events); attributes `Position`, `Size`, `Frame`, `Subrole`, `Enabled`, `Help`, `Parent`,
`TopLevelUIElement`; role `AXButton`; stack-container children/expand action and panel-level
`Clear All`.
