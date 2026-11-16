# How to behave

Read README.md.

## Docs

Requirements live in `docs/` in EARS syntax. Every directory has an `_index.md` — read it first.
Feature requirements live under `docs/features/<name>/`. The flow is: EARS requirements → BDD
acceptance scenarios (`.feature`) → implementation. Acceptance scenarios are the executable spec;
code exists to make them pass.

Docs explain **what** the app does, not **how**: describe capabilities and external surface — no
`file:line` citations, internal symbol names, or code-structure narration. Architecture and
constraint facts belong in `docs/constraints.md` and feature `description.md`, not in user-facing
prose. Keep code and docs in sync: a change that renames or moves code, or adds a constraint,
updates every doc that references it (README, CLAUDE.md, `docs/`) in the same change.

## Testing

Three tiers (see [`docs/testing.md`](docs/testing.md)): **unit** (swift-testing, no AX),
**AX-integration** (swift-testing against real Notification Center, gated on Accessibility trust),
**acceptance** (cucumber-js driving the compiled `nbk` binary as a black box). Test at the lowest
tier that can prove the behavior; push logic into `NotificationCore` and unit-test it test-first
(TDD) whenever practical. Run with `./build.ps1 -DoTest` (`-Kinds Unit|Integration|Acceptance|All`).

CI runs the **unit tier only** — AX-integration and acceptance need Accessibility trust and a real
Notification Center, which hosted runners can't provide. A green CI therefore does **not** exercise
the acceptance harness, so verify dependency bumps that touch it (e.g. cucumber-js) locally with
`./build.ps1 -DoTest -Kinds Acceptance`.

## Mechanism

Interaction with notifications is **Accessibility-API only** ([C-1](docs/constraints.md)) — no
screenshots/OCR, no fixed-coordinate mouse simulation, no private APIs. One exception: opening the
Notification Center panel uses a synthetic mouse click on the menu bar clock, positioned from the
clock's AX frame at click time; everything done to a notification stays AX-only. The AX hierarchy of
Notification Center is version-sensitive ([C-3](docs/constraints.md)); locate elements structurally,
never by hardcoded pid/index. Two known quirks live in the AX adapter: focus-before-close, and
poll-for-render-delay.

## Code style

Default to no comments. Reserve them for the genuinely non-obvious, and keep them minimal — a clear
name or structure beats a comment. Don't add comments that restate what the code/test already says.
Don't reference requirement IDs (`RNA-*`) in production code comments; citing the req a test
validates is fine in test comments.

## Committing & Pushing

- Before committing, run `./build.ps1 -DoLint` and `./build.ps1 -DoTest` (builds, then runs all test
  tiers) and fix any failures. Never commit code that does not build, lint clean, and pass tests.
  - Exception: a change touching only markdown needs `./build.ps1 -DoLint` alone. Anything touching
    Swift, scripts, `.feature` files or test support still gets the full run.
  - While iterating on visual tweaks (tint, spacing, look), build and screenshot per tweak; run lint
    and the full suite once before committing, or as soon as logic changes.
- Label every PR so the auto-generated release notes (`.github/release.yml`) categorize it — the
  changelog is label-driven, not commit-title-driven: feature → `enhancement`, bugfix → `bug`, docs
  → `documentation`, CI/chore/tooling → `chore`. Unlabelled PRs land in "Other Changes". `ignore`
  (excluded from the changelog) is for the automated version-bump and merge-back PRs only.
- Only commit if explicitly allowed by the human.
- Only push if explicitly allowed by the human.
- Use [Conventional Commits](https://www.conventionalcommits.org) (`type: subject`, e.g. `feat:`,
  `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `ci:`, `build:`), single-line.
- Never include yourself as co-author.
- `main` is protected by a repo ruleset (required status checks, strict up-to-date). Land work by
  rebasing onto `origin/main`, pushing, then arming squash auto-merge
  (`gh pr merge --squash --auto`) — it merges once checks go green. Never `--admin`-bypass the
  ruleset without an explicit instruction.
