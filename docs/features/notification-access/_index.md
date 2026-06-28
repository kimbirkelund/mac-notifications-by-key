# Notification access

Feature code: **`NA`** (requirement IDs `RNA-*`; see [conventions](../../conventions.md)).

**Notification access** is the core capability: read the notifications macOS is currently
presenting, and act on a designated one — dismiss it, trigger one of its named actions, or activate
it (default action). It is the foundation every later feature builds on, and the first concrete
realization of the Accessibility-API-only mechanism ([C-1](../../constraints.md)).

- [Description](description.md) — how it works (prose, mental model).
- [Requirements](requirements.md) — behavioral requirements (`RNA-*`) and open seeds.
- [Acceptance scenarios](acceptance/_index.md) — BDD scenarios. The walking-skeleton `list` scenario
  is the first executable target; act/error scenarios are `@wip` until the corresponding CLI
  subcommands exist.

Honors the global [constraints](../../constraints.md) (notably C-1 AX-only, C-2 permission, C-3 OS
resilience), [cross-cutting requirements](../../cross-cutting.md) (X-1 single-invocation, X-2
machine-readable, X-3 safe failure, X-4 permission preflight), and
[definitions](../../definitions.md).
