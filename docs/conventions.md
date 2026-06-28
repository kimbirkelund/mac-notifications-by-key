# Documentation conventions

Authoritative rules for how requirements are identified and organized. All docs under `docs/` follow
these.

## Requirement identifiers

Every requirement and constraint has a **stable ID**. IDs are referenced from acceptance scenarios
and never reused once retired.

| ID form | Scope       | Kind                                                      | Acceptance test? |
| ------- | ----------- | --------------------------------------------------------- | ---------------- |
| `C-N`   | Global      | Non-functional **c**onstraint                             | No               |
| `X-N`   | Global      | **C**ross-cutting behavioral requirement (spans features) | Yes              |
| `R-N`   | Global      | Behavioral **r**equirement (not tied to one feature)      | Yes              |
| `RF-N`  | Feature `F` | Feature behavioral **r**equirement                        | Yes              |

- **Kind-first letter.** The leading letter states the kind (`R` requirement, `C` constraint, `X`
  cross-cutting), so global `R-N` and feature `RF-N` both read as "this is a requirement" at a
  glance.
- **`F` is a feature code** — see below. Example: in the `notification-access` feature (code `NA`),
  requirements are `RNA-1`, `RNA-2`, …
- **No feature-level cross-cutting (`XF-N`).** Cross-cutting is global _by definition_. A concern
  scoped to one feature is just an `RF-N`.
- **Feature-level constraints** are not used yet. If a non-functional property scoped to a single
  feature ever arises it would take the form `CF-N`; until then treat all constraints as global
  `C-N`.
- **Bare `R-N` is reserved for true global requirements** (currently none). Behavior that belongs to
  a feature uses `RF-N`, even if that feature is the only one that exists.

## Feature codes

Each feature has a **2-character uppercase code**, unique across all features.

- Registered in [`features/_index.md`](features/_index.md) (the `Code` column).
- Declared in the feature's own `_index.md`.
- Used to form that feature's requirement IDs (`RF-N`).

| Feature             | Code |
| ------------------- | ---- |
| Notification access | `NA` |

(The registry in `features/_index.md` is the source of truth; this table is illustrative.)

## EARS pattern tags

Each behavioral requirement is tagged with its EARS pattern — `(ubiquitous)`, `(event)`, `(state)`,
`(unwanted)`, `(optional)`, or `(complex)`. Tags are orthogonal to the ID scheme. A requirement may
also be tagged `deferred` when it depends on a capability not yet targeted; note what it depends on.

## Organization

- Global [constraints](constraints.md) (`C-*`), [cross-cutting requirements](cross-cutting.md)
  (`X-*`), and [definitions](definitions.md) live at the top level.
- Feature-specific requirements live under `docs/features/<name>/`.
- Every directory has an `_index.md`; read it first.
