# Notification access

Feature code: **`NA`** (requirement IDs `RNA-*`; see [conventions](../../conventions.md)).

**Notification access** is the core capability: read the notifications macOS is currently
presenting, and act on a designated one — dismiss it, trigger one of its named actions, or activate
it (default action). It is the foundation every later feature builds on.

- [Description](description.md) — how it works (prose, mental model).
- [Requirements](requirements.md) — behavioral requirements (`RNA-*`) and open seeds.
- [Acceptance scenarios](acceptance/_index.md) — BDD scenarios. The walking-skeleton `list` scenario
  is the first executable target; act/error scenarios are `@wip` until the corresponding CLI
  subcommands exist.
