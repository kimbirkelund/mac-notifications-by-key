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

  # Validates RIM-1 (stacking) and RIM-2: the panel stays above the overlay,
  # untinted, and the overlay is translucent rather than opaque. Needs the
  # window-list helper — window level and alpha are not exposed through AX.
  Scenario: The panel sits above the overlay, untinted
    Given interactive mode is running
    Then the Notification Center panel is above the overlay in the window order
    And the overlay is translucent

  # Validates RIM-10: one panel per presented notification, listing Activate,
  # Dismiss, then that notification's actions, immediately left of it and
  # top-aligned. Listing first waits out the banner render delay.
  Scenario: Each presented notification gets an action panel
    Given a notification is delivered with title "PanelOne"
    And a notification is delivered with title "PanelTwo"
    And I run "nbk list --wait 5"
    And interactive mode is running
    Then one action panel is present per presented notification
    And each panel lists "Activate", "Dismiss", then that notification's actions in order
    And each panel sits to the left of its notification with the same top edge

  # Validates RIM-10: with nothing presented there is nothing to attach a panel to.
  Scenario: No action panel when nothing is presented
    Given no notifications are presented
    And interactive mode is running
    Then no action panel is present

  # Validates RIM-11: on entering the mode the newest notification is selected,
  # and only one panel is selected at a time.
  Scenario: The newest notification is selected on entry
    Given a notification is delivered with title "SelectOne"
    And I run "nbk list --wait 5"
    And interactive mode is running
    Then exactly one action panel is selected
    And the selected panel is the topmost panel

  # Validates RIM-13: the selected panel shows a lower-case key left of each entry.
  # Script Editor's notification exposes Show Details, Show and Close.
  Scenario: The selected panel shows lower-case activators
    Given a notification is delivered with title "ActivatorOne"
    And I run "nbk list --wait 5"
    And interactive mode is running
    Then the selected panel shows activator "Space" before "Activate"
    And the selected panel shows activator "d" before "Dismiss"
    And the selected panel shows activator "s" before "Show Details"
    And the selected panel shows activator "h" before "Show"
    And the selected panel shows activator "c" before "Close"

  # Validates RIM-12: with one notification presented it is both first and last,
  # so every movement key must leave the selection where it is. This only guards
  # against wrap-around or a crash; movement between notifications is verified
  # live, because the harness cannot present a second one.
  Scenario: Moving the selection clamps at the ends
    Given a notification is delivered with title "MoveOne"
    And I run "nbk list --wait 5"
    And interactive mode is running
    And the overlay is the frontmost application
    When I press "j"
    Then the selection is unchanged
    When I press the Down arrow
    Then the selection is unchanged
    When I press the Up arrow
    Then the selection is unchanged
    When I press "k"
    Then the selection is unchanged

  # Validates RIM-17: a key that is bound to nothing does nothing.
  Scenario: Unbound keys are ignored
    Given a notification is delivered with title "UnboundOne"
    And I run "nbk list --wait 5"
    And interactive mode is running
    And the overlay is the frontmost application
    When I press "x"
    Then interactive mode is still running
    And the selection is unchanged
    And exactly one overlay window is present

  # Validates RIM-14: d performs Dismiss on the selected notification and the mode stays.
  Scenario: Pressing d dismisses the selected notification
    Given a notification is delivered with title "DismissByKey"
    And I run "nbk list --wait 5"
    And the JSON output contains a notification with title "DismissByKey"
    And interactive mode is running
    And the overlay is the frontmost application
    When I press "d"
    Then the notification titled "DismissByKey" is no longer presented
    And interactive mode is still running

  # Validates RIM-14: c performs the named action Close and the mode stays.
  Scenario: Pressing a named action's key performs it
    Given a notification is delivered with title "CloseByKey"
    And I run "nbk list --wait 5"
    And the JSON output contains a notification with title "CloseByKey"
    And interactive mode is running
    And the overlay is the frontmost application
    When I press "c"
    Then the notification titled "CloseByKey" is no longer presented
    And interactive mode is still running

  # Validates RIM-14: Space performs Activate and the mode stays; the notification is removed
  # once the mode exits.
  Scenario: Pressing Space activates the selected notification
    Given a notification is delivered with title "ActivateByKey"
    And I run "nbk list --wait 5"
    And the JSON output contains a notification with title "ActivateByKey"
    And interactive mode is running
    And the overlay is the frontmost application
    When I press "Space"
    Then interactive mode is still running
    When interactive mode is sent SIGTERM
    Then interactive mode exits with status 0
    And the notification titled "ActivateByKey" is no longer presented

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
