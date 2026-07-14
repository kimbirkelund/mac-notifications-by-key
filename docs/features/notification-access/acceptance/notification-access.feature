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

  # Validates RNA-2: with nothing presented, `list` emits an empty array, exit 0.
  Scenario: Listing is empty when nothing is presented
    # RNA-2
    Given no notifications are presented
    When I run "nbk list"
    Then the command succeeds
    And the JSON output is an empty array

  # Validates RNA-4: dismiss the notification at index 0 (the newest), exit 0,
  # and it is no longer presented.
  Scenario: Dismissing the newest notification removes it
    # RNA-4
    Given a notification is delivered with title "DismissMe"
    And I run "nbk list --wait 5"
    When I run "nbk dismiss 0"
    Then the command succeeds
    And I run "nbk list"
    And the JSON output does not include a notification with title "DismissMe"

  # Validates RNA-5: perform a named action the notification exposes, exit 0.
  # A Script Editor notification exposes "Show Details", "Show", "Close".
  Scenario: Triggering a named action on a notification
    # RNA-5
    Given a notification is delivered with title "ActOnMe"
    And I run "nbk list --wait 5"
    When I run "nbk action 0 \"Show\""
    Then the command succeeds

  # Validates RNA-6: default activation (AXPress) on a notification, exit 0.
  Scenario: Activating a notification with press
    # RNA-6
    Given a notification is delivered with title "PressMe"
    And I run "nbk list --wait 5"
    When I run "nbk press 0"
    Then the command succeeds

  # Validates RNA-7: designating an index with no notification present is a safe
  # failure — no action, non-zero exit, error names the bad index.
  Scenario: Designating an out-of-range index fails safely
    # RNA-7 — no action, non-zero exit, nothing else dismissed
    Given no notifications are presented
    When I run "nbk dismiss 0"
    Then the command fails
    And the error output mentions an out-of-range index

  # Validates RNA-8: performing an action the notification does not expose fails,
  # naming the available actions, and performs nothing.
  Scenario: Triggering an unknown action fails and lists what is available
    # RNA-8
    Given a notification is delivered with title "UnknownActionMe"
    And I run "nbk list --wait 5"
    When I run "nbk action 0 \"NoSuchAction\""
    Then the command fails
    And the error output lists the available actions

  # Validates RNA-10: doctor reports trust, the resolved Notification Center
  # process, and the running macOS version.
  Scenario: Doctor reports the environment
    # RNA-10
    When I run "nbk doctor"
    Then the command succeeds
    And the doctor output reports trust, the Notification Center process, and the macOS version

  # RNA-9 — there is no programmatic API to revoke Accessibility trust, so this
  # scenario substitutes a human operator for that step. It is @operator (excluded
  # from the default/CI run) and attended: run it on demand with
  #   npx cucumber-js -p operator
  # The operator revokes trust when prompted; the run restores it afterwards.
  @operator
  Scenario: Missing Accessibility trust is reported
    # RNA-9 — run in a host without AX trust
    Given the operator has revoked Accessibility trust for the test runner
    When I run "nbk list"
    Then the command fails
    And the error output explains how to grant Accessibility permission
