# Notification access — Requirements

Behavioral requirements for notification access (feature code `NA`). See
[conventions](../../conventions.md) for the ID scheme and [foundations](../../_index.md#foundations)
for `C-*`/`X-*`.

## Read

- **RNA-1 (event) — List presented notifications.** When the user runs `list`, the system shall
  emit, as JSON ([X-2](../../cross-cutting.md)), the notifications currently presented by
  Notification Center — newest first — each with its app, title, subtitle, body, available action
  names, and a 0-based index.
- **RNA-2 (state) — Empty when none presented.** While no notifications are presented, `list` shall
  emit an empty JSON array and exit `0`.
- **RNA-3 (optional) — Wait for delivery.** Where a `--wait <seconds>` option is given, the system
  shall poll for up to that duration for a notification to be presented before concluding the set is
  empty ([C-3](../../constraints.md) render delay).

## Act

- **RNA-4 (event) — Dismiss by index.** When the user runs `dismiss <n>`, the system shall dismiss
  the notification at index `n` (focusing the element first, per the AX `Close` quirk) and exit `0`.
- **RNA-5 (event) — Trigger a named action.** When the user runs `action <n> <name>`, the system
  shall perform the action `<name>` on the notification at index `n`, provided that notification
  exposes it.
- **RNA-6 (event) — Activate.** When the user runs `press <n>`, the system shall perform the default
  activation (`AXPress`) on the notification at index `n`.

## Safe failure

- **RNA-7 (unwanted) — Index out of range.** If the user designates an index `n` for which no
  notification is present, then the system shall report the error on stderr, perform no action, and
  exit non-zero ([X-3](../../cross-cutting.md)).
- **RNA-8 (unwanted) — Unknown action name.** If the user runs `action <n> <name>` where
  notification `n` does not expose `<name>`, then the system shall report the error (listing the
  available action names) and exit non-zero, performing no action.

## Permission

- **RNA-9 (unwanted) — Missing Accessibility trust.** If any operation is invoked while the host
  lacks Accessibility trust ([C-2](../../constraints.md)), then the system shall report the missing
  permission and how to grant it, and exit non-zero, rather than returning empty or misleading
  results ([X-4](../../cross-cutting.md)).
- **RNA-10 (event) — Doctor.** When the user runs `doctor`, the system shall report whether
  Accessibility trust is granted, the resolved Notification Center process, and the running macOS
  version.

## Open seeds (not yet specified)

- **Watch/daemon mode** — a long-running mode that reacts to notifications as they arrive, rather
  than one-shot invocations.
- **Selection by app/content** — designating a notification by matching app or text instead of by
  index.
- **Persistent-panel history** — reading dismissed/older notifications from the Notification Center
  panel beyond what is currently presented.
- **Inline reply** — using a notification's reply action to send text.
