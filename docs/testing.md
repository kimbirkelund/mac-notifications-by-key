# Testing strategy

The tool tests in three tiers. Each tier tests a different **boundary**; together they form a
pyramid (many fast unit tests, fewer AX-integration tests, few acceptance tests). Write tests at the
**lowest tier that can prove the behavior** — push logic down into pure modules so it can be
unit-tested rather than only exercised end-to-end.

## The tiers

| Tier               | Tool                                                    | Environment                                          | Owns                                                                                                | Lives in                                                                    |
| ------------------ | ------------------------------------------------------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| **Unit**           | [swift-testing](https://github.com/apple/swift-testing) | node-free, fast, no AX                               | Pure logic — argument parsing, notification-model decoding, selection/index rules, JSON output      | `Tests/NotificationCoreTests/` (tests the `NotificationCore` target)        |
| **AX-integration** | swift-testing (gated)                                   | real Notification Center + AX trust                  | The AX adapter against real notifications: reading the live tree into the model, focus+close/action | `Tests/NotificationAXIntegrationTests/` (tests the `NotificationAX` target) |
| **Acceptance**     | [cucumber-js](https://github.com/cucumber/cucumber-js)  | real macOS, the compiled `nbk` binary as a black box | End-to-end behavior: deliver a real notification, invoke the CLI, assert observable result          | `docs/features/**/acceptance/*.feature` + steps in `acceptance/steps/`      |

## The boundary, in one line

- **Unit** — is this rule/parse/format correct? (the logic)
- **AX-integration** — does the AX adapter read and act on the real tree correctly? (the mechanism)
- **Acceptance** — does the whole CLI actually do it, end to end? (the real effect)

A rule lives in **one** place: pure logic in `NotificationCore` (unit-tested); the `NotificationAX`
adapter is tested only for reading/acting on the real tree; the acceptance scenario proves the real
effect through the shipped binary. Don't re-enumerate unit cases at the AX-integration tier, or AX
cases at the acceptance tier.

## Gating (AX-integration & acceptance)

The AX-integration and acceptance tiers require a **real Notification Center** and **Accessibility
trust** for the test host ([C-2](constraints.md)), and they **deliver real notifications** (via
`osascript -e 'display notification …'`) and account for banner render delay ([C-3](constraints.md),
the `--wait` behavior). These tiers are therefore environment-dependent: `build.ps1` preflights AX
trust and skips them with a clear message when it is absent, rather than reporting false failures.

## TDD

Unit-tier logic is developed **test-first (red → green → refactor) whenever practical** — write the
failing test, then the implementation. This is the main reason to push logic into `NotificationCore`
as pure functions over plain model types: it makes test-first cheap and keeps the irreducibly-impure
AX code thin.

## Worked example — `nbk list`

- **Unit** (`NotificationCoreTests`): decoding a captured AX element description into a
  `Notification` model; rendering a list of `Notification` to the documented JSON shape;
  newest-first ordering and index assignment.
- **AX-integration** (`NotificationAXIntegrationTests`): with one delivered notification present,
  the adapter reads exactly one `Notification` whose title matches; `Close` after focusing removes
  it (count 1 → 0).
- **Acceptance** (`notification-access/acceptance/list.feature`): deliver a notification, run
  `nbk list`, assert the JSON output contains it.

## Running

| Command                                      | Runs                                         |
| -------------------------------------------- | -------------------------------------------- |
| `./build.ps1 -DoTest`                        | all three tiers (`-Kinds All`, the default)  |
| `./build.ps1 -DoTest -Kinds Unit`            | unit only                                    |
| `./build.ps1 -DoTest -Kinds Integration`     | AX-integration only (needs AX trust)         |
| `./build.ps1 -DoTest -Kinds Acceptance`      | cucumber-js acceptance only (needs AX trust) |
| `./build.ps1 -DoTest -Kinds Unit,Acceptance` | a subset (comma-separated)                   |

`-Kinds` accepts `All` (default), `Unit`, `Integration`, `Acceptance`. The underlying commands are
`swift test --filter NotificationCoreTests`, `swift test --filter NotificationAXIntegrationTests`,
and `npx cucumber-js`. `@wip` scenarios are excluded from the acceptance run via `tags: 'not @wip'`
in `cucumber.mjs`.
