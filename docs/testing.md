# Testing strategy

The tool tests in three tiers. Each tier tests a different **boundary**; together they form a
pyramid (many fast unit tests, fewer AX-integration tests, few acceptance tests). Write tests at the
**lowest tier that can prove the behavior** — push logic down into pure modules so it can be
unit-tested rather than only exercised end-to-end.

## The tiers

| Tier               | Tool                                                    | Environment                                          | Owns                                                                                                                                                                             | Lives in                                                                                                                                |
| ------------------ | ------------------------------------------------------- | ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **Unit**           | [swift-testing](https://github.com/apple/swift-testing) | node-free, fast, no AX                               | Pure logic — argument parsing, notification-model decoding, selection/index rules, JSON output; plus AX-module seam logic that makes no Accessibility calls (the access factory) | `Tests/NotificationCoreTests/` (the `NotificationCore` target) and `Tests/NotificationAXUnitTests/` (the `NotificationAX` factory/seam) |
| **AX-integration** | swift-testing (gated)                                   | real Notification Center + AX trust                  | The AX adapter against real notifications: reading the live tree into the model, focus+close/action                                                                              | `Tests/NotificationAXIntegrationTests/` (tests the `NotificationAX` target)                                                             |
| **Acceptance**     | [cucumber-js](https://github.com/cucumber/cucumber-js)  | real macOS, the compiled `nbk` binary as a black box | End-to-end behavior: deliver a real notification, invoke the CLI, assert observable result                                                                                       | `docs/features/**/acceptance/*.feature` + steps in `acceptance/steps/`                                                                  |

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

They also drive the real screen, so `build.ps1` guards every run of them, whether started by a
person or an agent. It refuses to start them, with a clear message, unless the invoking user owns
the console session and the screen is unlocked. While they run it keeps the display and the machine
awake (`caffeinate`) and shows a small "Tests running — hands off" sign that never takes focus or
clicks; both go away when the run ends, fails or is interrupted. The unit tier does none of this.

## Fixture-driven acceptance (demo mode)

Notification Center cannot be made to present a controlled set of notifications: every notification
the harness delivers is attributed to Script Editor and collapses into one stack, so only one is
ever presented, and what it exposes is fixed. Behavior that depends on the notification set (moving
the selection, selection after removal, activator assignment, which entries close a notification) is
therefore driven through **demo mode** ([RIM-21](features/interactive-mode/requirements.md)): the
scenario starts the demo application, `demo-nc`, with a fixture file from `acceptance/fixtures/`. By
default it starts with its list closed: the harness waits for its menu bar item, starts
`interactive --demo`, and waits for the mode to open the list with the fixture's notifications. A
scenario that says the demo list starts open launches `demo-nc --open` instead, waits for the list,
and only then starts the mode. The notifications, their actions and whether each entry closes are
exactly what the fixture says. The demo application exposes them through the Accessibility API like
Notification Center, so `nbk` reads and acts on them through its real adapter. Teardown stops both
processes. Scenarios that use a fixture never run `nbk list`. Tag them `@demo`: the hooks then skip
the Notification Center clearing (which opens and closes the panel) around them and only stop the
mode and the demo application. The harness reads the overlay windows and their action panels from
`nbk`, and the notification boxes from the demo application's window, through `axdump`, a small
helper built next to `nbk` that dumps the accessibility windows of a process in one pass, together
with the menu bar items the process owns (the harness uses the demo application's item to tell that
it is ready, and its window to tell whether its list is open).

Demo mode proves the key handling, selection and panel logic of the overlay, and that entries act on
the list the way the file says. It does not prove that Notification Center's accessibility tree is
read, dismissed, pressed or acted on correctly, that the panel is opened and closed, or that panels
line up with the real notification boxes. The panel open/close contract of the session is
unit-tested, and the real adapter's open/close is AX-integration-tested. The one acceptance scenario
that still runs against the real Notification Center is the window-order scenario, which checks that
the panel sits above the overlay, untinted.

## Attended (@operator) scenarios

**Last resort only, and only after checking with the human.** An attended scenario trades away
unattended/CI execution, so first exhaust the alternatives: push the logic to a tier with an API
(unit/AX-integration), find a programmatic substitute, or leave the requirement uncovered with a
note. Propose an `@operator` scenario to the human and get agreement before writing one.

When a scenario genuinely needs a step with no programmatic API (e.g. revoking Accessibility trust),
substitute a human operator rather than dropping the requirement. Conventions:

- Tag `@operator`; exclude from the default/CI run. cucumber-js ANDs config `tags` with CLI
  `--tags`, so expose a named profile instead of a tag flag: run with
  `./build.ps1 -DoTest -Kinds Operator`, which wraps `npx cucumber-js -p operator`.
- Block for real: read `/dev/tty` synchronously, not `process.stdin` (cucumber detaches it).
- Set `timeout: -1` on the attended step/hook — the human wait exceeds the 5s cap.
- Verify the substituted precondition by ground truth (`nbk doctor`), looping until it agrees. Do
  not guess the environment (`TERM_PROGRAM` / ppid are unreliable under multiplexers and
  reparenting).
- Always restore what you changed in an `@operator`-scoped `After` (also verify-looped), so a
  timed-out or failed run can't leave the machine altered.

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

| Command                                      | Runs                                                        |
| -------------------------------------------- | ----------------------------------------------------------- |
| `./build.ps1 -DoTest`                        | all three tiers (`-Kinds All`, the default)                 |
| `./build.ps1 -DoTest -Kinds Unit`            | unit only                                                   |
| `./build.ps1 -DoTest -Kinds Integration`     | AX-integration only (needs AX trust)                        |
| `./build.ps1 -DoTest -Kinds Acceptance`      | cucumber-js acceptance only (needs AX trust)                |
| `./build.ps1 -DoTest -Kinds Unit,Acceptance` | a subset (comma-separated)                                  |
| `./build.ps1 -DoTest -Kinds Operator`        | attended `@operator` scenarios (needs AX trust and a human) |

`-Kinds` accepts `All` (default), `Unit`, `Integration`, `Acceptance`, `Operator`. `All` never
includes `Operator`, because it waits for a human at the terminal. The underlying commands are
`swift test --filter NotificationCoreTests --filter NotificationAXUnitTests --filter InteractiveModeTests`,
`swift test --filter NotificationAXIntegrationTests`, and `npx cucumber-js`. `@wip` and `@operator`
scenarios are excluded from the acceptance run via `tags` in `cucumber.mjs`.
