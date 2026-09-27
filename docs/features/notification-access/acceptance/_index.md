# Notification access — Acceptance scenarios

BDD scenarios (Gherkin) specifying notification access. These `.feature` files **are** the
executable acceptance tests: [cucumber-js](https://github.com/cucumber/cucumber-js) runs them
against the compiled `nbk` binary as a black box, using the step definitions in `acceptance/steps/`.
Steps deliver real notifications (`osascript -e 'display notification …'`) and assert the CLI's
observable output and exit status.

| Scenario                                                 | Validates    | Status                                         |
| -------------------------------------------------------- | ------------ | ---------------------------------------------- |
| Listing includes a delivered notification                | RNA-1, RNA-3 | ✅                                             |
| Waiting catches a notification delivered after start     | RNA-3        | ✅                                             |
| Listing is empty when nothing is presented               | RNA-2        | ✅                                             |
| Dismissing the newest notification removes it            | RNA-4        | ✅                                             |
| Triggering a named action on a notification              | RNA-5        | ✅                                             |
| Activating a notification with press                     | RNA-6        | ✅                                             |
| Designating an out-of-range index fails safely           | RNA-7        | ✅                                             |
| Triggering an unknown action fails and lists what exists | RNA-8        | ✅                                             |
| Doctor reports the environment                           | RNA-10       | ✅                                             |
| Missing Accessibility trust is reported                  | RNA-9        | ✅ `@operator` — attended; last run 2026-09-27 |

## Walking skeleton

The first milestone was only that `nbk list` reads the currently-presented notifications and prints
them as JSON. That scenario delivers one notification, runs `nbk list --wait 5`, and asserts the
output contains a notification with the delivered title. It wired the whole chain end to end: the
Swift CLI, the `NotificationAX` adapter, AX trust, banner-render polling, and the cucumber-js
harness. The act/error scenarios followed once `dismiss`/`action`/`press` existed; all unattended
scenarios now run in the default acceptance run.

## Notes

- `@wip` and `@operator` scenarios are excluded from the default run via `tags` in `cucumber.mjs`;
  the trust scenario is attended only (`npx cucumber-js -p operator`, or
  `./build.ps1 -DoTest -Kinds Operator`).
- Scenarios assert against the **JSON output and exit status** of the binary, not against any UI
  wording, to keep them decoupled from macOS copy.
- The tier is environment-dependent (real Notification Center + AX trust); see
  [testing](../../../testing.md) gating.
