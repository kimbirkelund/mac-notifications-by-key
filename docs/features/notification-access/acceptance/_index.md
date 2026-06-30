# Notification access — Acceptance scenarios

BDD scenarios (Gherkin) specifying notification access. These `.feature` files **are** the
executable acceptance tests: [cucumber-js](https://github.com/cucumber/cucumber-js) runs them
against the compiled `nbk` binary as a black box, using the step definitions in `acceptance/steps/`.
Steps deliver real notifications (`osascript -e 'display notification …'`) and assert the CLI's
observable output and exit status.

| Scenario                                       | Validates    | Status                                              |
| ---------------------------------------------- | ------------ | --------------------------------------------------- |
| Listing includes a delivered notification      | RNA-1, RNA-3 | ✅ Executable (walking skeleton: `nbk list --wait`) |
| Listing is empty when nothing is presented     | RNA-2        | ✅ Executable (`nbk list` emits `[]`)               |
| Dismissing the newest notification removes it  | RNA-4        | 🚧 `@wip` — until `dismiss` is built                |
| Triggering a named action                      | RNA-5        | 🚧 `@wip`                                           |
| Designating an out-of-range index fails safely | RNA-7        | 🚧 `@wip`                                           |
| Missing Accessibility trust is reported        | RNA-9        | 🚧 `@wip` — needs a no-trust harness                |

## Walking skeleton

The first milestone is only that `nbk list` reads the currently-presented notifications and prints
them as JSON. The scenario delivers one notification, runs `nbk list --wait 5`, and asserts the
output contains a notification with the delivered title. This wires the whole chain end to end: the
Swift CLI, the `NotificationAX` adapter, AX trust, banner-render polling, and the cucumber-js
harness. The act/error scenarios follow once `dismiss`/`action`/`press` exist.

## Notes

- `@wip` scenarios are excluded from the run via `tags: 'not @wip'` in `cucumber.mjs`, so their
  not-yet-defined steps do not fail the suite.
- Scenarios assert against the **JSON output and exit status** of the binary, not against any UI
  wording, to keep them decoupled from macOS copy.
- The tier is environment-dependent (real Notification Center + AX trust); see
  [testing](../../../testing.md) gating.
