Feature: Notification access
  As someone driving macOS notifications from the keyboard
  I want to read and act on presented notifications from the CLI
  So that I can bind notification operations to hotkeys

  # Walking skeleton (validates RNA-1, RNA-3): a delivered notification appears in
  # `nbk list` output. Accounts for banner render delay via --wait.
  Scenario: Listing includes a delivered notification
    Given a notification is delivered with title "AcceptanceProbe"
    When I run "nbk list --wait 5"
    Then the command succeeds
    And the JSON output contains a notification with title "AcceptanceProbe"

  # Validates RNA-3: --wait polls past delivery/render delay, catching a
  # notification that only arrives after the command has already started.
  Scenario: Waiting catches a notification delivered after the command starts
    Given no notifications are presented
    When a notification with title "SlowProbe" is delivered after 2 seconds
    And I run "nbk list --wait 8"
    Then the command succeeds
    And the JSON output includes a notification with title "SlowProbe"

  # The @wip scenarios below are the agreed specification for the rest of the feature
  # (RNA-4,5,7,9). They are excluded until the corresponding subcommands exist; their
  # step wording will be refined against the real CLI.

  # Validates RNA-2: with nothing presented, `list` emits an empty array, exit 0.
  Scenario: Listing is empty when nothing is presented
    # RNA-2
    Given no notifications are presented
    When I run "nbk list"
    Then the command succeeds
    And the JSON output is an empty array

  @wip
  Scenario: Dismissing the newest notification removes it
    # RNA-4
    Given a notification is delivered with title "DismissMe"
    And I run "nbk list --wait 5"
    When I run "nbk dismiss 0"
    Then the command succeeds
    And "nbk list" does not contain a notification with title "DismissMe"

  @wip
  Scenario: Triggering a named action on a notification
    # RNA-5
    Given a notification is delivered with title "ActOnMe"
    And I run "nbk list --wait 5"
    When I run "nbk action 0 \"Show\""
    Then the command succeeds

  @wip
  Scenario: Designating an out-of-range index fails safely
    # RNA-7 — no action, non-zero exit, nothing else dismissed
    Given no notifications are presented
    When I run "nbk dismiss 0"
    Then the command fails
    And the error output mentions an out-of-range index

  @wip
  Scenario: Missing Accessibility trust is reported
    # RNA-9 — run in a host without AX trust
    Given the host lacks Accessibility trust
    When I run "nbk list"
    Then the command fails
    And the error output explains how to grant Accessibility permission
