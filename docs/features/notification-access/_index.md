# Notification access

Feature code: **`NA`** (requirement IDs `RNA-*`; see [conventions](../../conventions.md)).

**Notification access** is the core capability: read the notifications macOS is currently
presenting, and act on a designated one — dismiss it, trigger one of its named actions, or activate
it (default action). It is the foundation every later feature builds on.

- [Description](description.md) — how it works (prose, mental model).
- [Requirements](requirements.md) — behavioral requirements (`RNA-*`) and open seeds.
- [Acceptance scenarios](acceptance/_index.md) — BDD scenarios. All unattended scenarios run in the
  default acceptance run; the missing-trust scenario is `@operator` and attended only.
