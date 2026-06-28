# How to behave

Read README.md.

## Docs

Requirements live in `docs/` in EARS syntax. Every directory has an `_index.md` — read it first.
Feature requirements live under `docs/features/<name>/`. The flow is: EARS requirements → BDD
acceptance scenarios (`.feature`) → implementation. Acceptance scenarios are the executable spec;
code exists to make them pass.

## Testing

Three tiers (see [`docs/testing.md`](docs/testing.md)): **unit** (swift-testing, pure logic in
`NotificationCore`), **AX-integration** (swift-testing against real Notification Center, gated on
Accessibility trust), **acceptance** (cucumber-js driving the compiled `nbk` binary as a black box).
Test at the lowest tier that can prove the behavior; push logic into `NotificationCore` and
unit-test it test-first (TDD) whenever practical. Run with `./build.ps1 -DoTest`
(`-Kinds Unit|Integration|Acceptance|All`).

## Mechanism

Interaction with notifications is **Accessibility-API only** ([C-1](docs/constraints.md)) — no
screenshots/OCR, no fixed-coordinate mouse simulation, no private APIs. The AX hierarchy of
Notification Center is version-sensitive ([C-3](docs/constraints.md)); locate elements structurally,
never by hardcoded pid/index. Two known quirks live in the AX adapter: focus-before-close, and
poll-for-render-delay.

## Committing & Pushing

- Before committing, run `./build.ps1 -DoLint` and `./build.ps1 -DoTest` (builds, then runs all test
  tiers) and fix any failures. Never commit code that does not build, lint clean, and pass tests.
- Only commit if explicitly allowed by the human.
- Only push if explicitly allowed by the human.
- Use [Conventional Commits](https://www.conventionalcommits.org) (`type: subject`, e.g. `feat:`,
  `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `ci:`, `build:`), single-line.
- Never include yourself as co-author.
