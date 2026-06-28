# mac-notifications-by-key — Documentation

A keyboard-driven tool for interacting with macOS notifications. It reads and acts on Notification
Center entries through the public Accessibility (AX) API and exposes those operations as a
non-interactive CLI suitable for binding to hotkeys (skhd). Requirements are written in EARS syntax
to guide which feature to work on and to generate BDD-style acceptance tests, which are made
executable and used as the basis for coding (see [README](../README.md)).

## Documentation convention

Every documentation directory has an `_index.md` that introduces the section and links its contents.
Leaf content lives in sibling files. **To understand a section, read its `_index.md` first.**

## Foundations

Global rules that apply across all features:

- [Conventions](conventions.md) — requirement ID scheme (`C-*`, `X-*`, `R-*`, `RF-*`) and feature
  codes. **Read before adding requirements.**
- [Testing strategy](testing.md) — the three test tiers (unit / AX-integration / acceptance), what
  each owns, and how to run them.
- [Constraints](constraints.md) — non-functional constraints (`C-*`) that inform architecture and
  mechanism selection.
- [Cross-cutting requirements](cross-cutting.md) — behavioral requirements (`X-*`) that apply to
  every feature.
- [Definitions](definitions.md) — shared domain vocabulary (Notification, Action, Banner,
  Notification Center).

## Features

See [features](features/_index.md) for the feature catalogue and per-feature requirements.

## Conventions

See [conventions](conventions.md) for the full requirement ID scheme and feature codes. In brief:
every requirement has a stable ID; behavioral requirements (`R-*`, `X-*`, `RF-*`) drive acceptance
tests, constraints (`C-*`) have no direct acceptance test; feature-specific requirements live under
`docs/features/<name>/`.
