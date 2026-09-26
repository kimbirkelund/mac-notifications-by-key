Feature: Interactive mode
  As someone driving macOS notifications from the keyboard
  I want a mode that signals notifications are the subject and keeps the panel open
  So that I can act on notifications without waiting for a banner to appear

  Background:
    Given interactive mode is not running

  # Validates RIM-1, RIM-5: entering the mode draws the overlay, takes focus, and
  # opens the Notification Center panel so a subject exists for the whole session.
  Scenario: Entering interactive mode shows the overlay and opens the panel
    When I start "nbk interactive"
    Then an overlay window covering the screen is present
    And the overlay is the frontmost application
    And the overlay shows the mode label
    And the Notification Center panel is open

  # Validates RIM-3: the mode holds focus without becoming an app you switch to.
  Scenario: The mode keeps no application presence
    When I start "nbk interactive"
    Then the mode presents no Dock icon and no menu bar

  # Validates RIM-4: a toggle hotkey pressed twice must not stack overlays. The
  # second invocation returns 0 and the first keeps owning the mode.
  Scenario: Re-invoking while the mode runs does not stack a second overlay
    Given interactive mode is running
    When I run "nbk interactive"
    Then the command succeeds
    And exactly one overlay window is present
    And interactive mode is still running

  # Validates RIM-6: signal teardown is complete — overlay gone, panel closed
  # (the panel outlives the process unless explicitly closed), exit 0.
  Scenario: Terminating on a signal removes the overlay and closes the panel
    Given interactive mode is running
    When interactive mode is sent SIGTERM
    Then interactive mode exits with status 0
    And no overlay window is present
    And the Notification Center panel is closed

  # Validates RIM-7: the exit that needs no hotkey daemon. Escape is posted as a
  # real key event; the frontmost check guards against sending it to another app.
  Scenario: Pressing Escape leaves the mode
    Given interactive mode is running
    And the overlay is the frontmost application
    When I press Escape
    Then interactive mode exits with status 0
    And no overlay window is present
    And the Notification Center panel is closed

  # Validates RIM-1 (stacking) and RIM-2: the overlay covers the panel yet leaves
  # it readable. Needs the window-list helper — window level and alpha are not
  # exposed through AX.
  Scenario: The overlay sits above the panel without hiding it
    Given interactive mode is running
    Then the overlay is above the Notification Center panel in the window order
    And the overlay is translucent

  # Validates RIM-9: entering a mode whose every operation would fail is refused.
  # @operator because there is no API to revoke Accessibility trust; a human does
  # it when prompted. Attended only: npx cucumber-js -p operator
  @operator
  Scenario: Missing Accessibility trust is refused before the overlay appears
    Given the operator has revoked Accessibility trust for the test runner
    When I run "nbk interactive"
    Then the command fails
    And the error output explains how to grant Accessibility permission
    And no overlay window is present
