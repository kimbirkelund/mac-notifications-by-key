Feature: Interactive mode
  As someone driving macOS notifications from the keyboard
  I want a mode that signals notifications are the subject and keeps the panel open
  So that I can act on notifications without waiting for a banner to appear

  Background:
    Given interactive mode is not running

  # Validates RIM-1: entering the mode draws the overlay and takes focus.
  @demo
  Scenario: Entering interactive mode shows the overlay
    Given interactive mode is running with demo file "one.json"
    Then an overlay window covering the screen is present
    And the overlay is the frontmost application
    And the overlay shows no label

  # Validates RIM-3: the mode holds focus without becoming an app you switch to.
  @demo
  Scenario: The mode keeps no application presence
    Given interactive mode is running with demo file "one.json"
    Then the mode presents no Dock icon and no menu bar

  # Validates RIM-4: a toggle hotkey pressed twice must not stack overlays. The
  # second invocation returns 0 and the first keeps owning the mode.
  @demo
  Scenario: Re-invoking while the mode runs does not stack a second overlay
    Given interactive mode is running with demo file "one.json"
    When I run "nbk interactive"
    Then the command succeeds
    And exactly one overlay window is present
    And interactive mode is still running

  # Validates RIM-6: signal teardown removes the overlay and exits 0. Closing the panel
  # is proven elsewhere: the unit tests show the screen release closes it exactly once and
  # that teardown performs that release, and the AX-integration tests show the real
  # adapter closes the panel.
  @demo
  Scenario: Terminating on a signal removes the overlay
    Given interactive mode is running with demo file "one.json"
    When interactive mode is sent SIGTERM
    Then interactive mode exits with status 0
    And no overlay window is present

  # Validates RIM-7: the exit that needs no hotkey daemon. Escape is posted as a
  # real key event; the frontmost check guards against sending it to another app.
  # Closing the panel is proven elsewhere: the unit tests show the screen release closes
  # it exactly once and that teardown performs that release, and the AX-integration tests
  # show the real adapter closes the panel.
  @demo
  Scenario: Pressing Escape leaves the mode
    Given interactive mode is running with demo file "one.json"
    And the overlay is the frontmost application
    When I press Escape
    Then interactive mode exits with status 0
    And no overlay window is present

  # Validates RIM-1 (stacking), RIM-2 and RIM-5: the mode opens the panel, which stays
  # above the overlay, untinted, and the overlay is translucent rather than opaque.
  # Needs the window-list helper — window level and alpha are not exposed through AX.
  # The only scenario that runs against the real Notification Center.
  Scenario: The panel sits above the overlay, untinted
    Given a notification is delivered with title "Order"
    And interactive mode is running
    Then the Notification Center panel is open
    And the Notification Center panel is above the overlay in the window order
    And the overlay is translucent

  # Validates RIM-10: one panel, beside the selected notification only, listing
  # Activate, Dismiss, then that notification's actions, immediately left of it,
  # top-aligned and no shorter than it.
  @demo
  Scenario: Only the selected notification gets an action panel
    Given interactive mode is running with demo file "three.json"
    Then exactly one action panel is present
    And the panel lists "Activate", "Dismiss this / app / all", then the selected notification's actions in order
    And the panel sits to the left of the selected notification with the same top edge
    And the panel is at least as tall as the selected notification

  # Validates RIM-10, RIM-16: with nothing presented there is nothing to attach a panel
  # to, and the mode has nothing left to be the subject of, so it ends.
  @demo
  Scenario: Nothing presented on entry ends the mode
    Given interactive mode is running with demo file "none.json"
    Then the overlay shows the label "No more jobs!"
    And no action panel is present
    And interactive mode exits with status 0
    And no overlay window is present

  # Validates RIM-16: dismissing the last notification empties the list and ends the mode.
  @demo
  Scenario: Dismissing the last notification ends the mode
    Given interactive mode is running with demo file "one.json"
    And the overlay is the frontmost application
    When I press "d"
    Then the overlay shows the label "No more jobs!"
    And no action panel is present
    And interactive mode exits with status 0
    And no overlay window is present

  # Validates RIM-16: Escape during the farewell does not wait for the fade.
  @demo
  Scenario: Escape during the farewell ends the mode at once
    Given interactive mode is running with demo file "none.json"
    And the overlay shows the label "No more jobs!"
    When I press Escape
    Then interactive mode exits with status 0

  # Validates RIM-11: on entering the mode the newest notification is selected,
  # and the one panel marks it. Fixture notifications, so there is more than one
  # to choose between.
  @demo
  Scenario: The newest notification is selected on entry
    Given interactive mode is running with demo file "three.json"
    Then exactly one action panel is selected
    And the panel sits beside the topmost notification
    And the Notification Center panel is closed

  # Validates RIM-13: the panel shows a lower-case key left of each entry.
  @demo
  Scenario: The selected panel shows lower-case activators
    Given the demo list starts open
    And interactive mode is running with demo file "one.json"
    Then the selected panel shows activator "space" before "Activate"
    And the selected panel shows activator "d / D / X" before "Dismiss this / app / all"
    And the selected panel shows activator "a" before "Archive"
    And the selected panel shows activator "n" before "Answer"
    And the selected panel shows activator "e" before "Delete"
    And the selected panel shows activator "r" before "Reply"
    And the selected panel shows activator "1" before "Ad"

  # Validates RIM-12: j/k and Down/Up move one step, and the ends clamp rather than wrap.
  @demo
  Scenario: Moving the selection between notifications
    Given the demo list starts open
    And interactive mode is running with demo file "three.json"
    And the overlay is the frontmost application
    When I press "j"
    Then the notification at position 2 is selected
    When I press the Down arrow
    Then the notification at position 3 is selected
    When I press "j"
    Then the selection is unchanged
    When I press the Up arrow
    Then the notification at position 2 is selected
    When I press "k"
    Then the topmost notification is selected
    When I press the Up arrow
    Then the selection is unchanged

  # Validates RIM-23: a hint shows only where the move would change the selection.
  @demo
  Scenario: Movement hints show only where a move is possible
    Given the demo list starts open
    And interactive mode is running with demo file "three.json"
    And the overlay is the frontmost application
    Then the panel does not show the "k" hint
    And the panel shows the "j" hint
    When I press "j"
    Then the panel shows the "k" hint
    And the panel shows the "j" hint
    When I press "j"
    Then the panel shows the "k" hint
    And the panel does not show the "j" hint

  # Validates RIM-17: a key that is bound to nothing does nothing.
  @demo
  Scenario: Unbound keys are ignored
    Given the demo list starts open
    And interactive mode is running with demo file "one.json"
    And the overlay is the frontmost application
    When I press "x"
    Then interactive mode is still running
    And the selection is unchanged
    And exactly one overlay window is present

  # Validates RIM-14, RIM-15: d performs Dismiss on the selected notification, the mode
  # stays, and the selection stays at the same position, now on the next notification.
  @demo
  Scenario: Pressing d dismisses the selected notification
    Given the demo list starts open
    And interactive mode is running with demo file "three.json"
    And the overlay is the frontmost application
    When I press "j"
    Then the notification at position 2 is selected
    When I press "d"
    Then the notification titled "Second" is no longer presented
    And the notification at position 2 is selected
    And interactive mode is still running

  # Validates RIM-24, RIM-21: the panel is gone while a slow entry removes its notification
  # and is drawn again once it has finished.
  @demo
  Scenario: The panel hides while an entry removes its notification
    Given the demo list starts open
    And interactive mode is running with demo file "slow-dismiss.json"
    And the overlay is the frontmost application
    When I press "d"
    Then the action panel is removed
    And no action panel is present
    And the notification titled "First" is no longer presented
    And exactly one action panel is present
    And interactive mode is still running

  # Validates RIM-14: a named action's key performs that action and the mode stays.
  @demo
  Scenario: Pressing a named action's key performs it
    Given the demo list starts open
    And interactive mode is running with demo file "three.json"
    And the overlay is the frontmost application
    When I press "a"
    Then the notification titled "First" is no longer presented
    And interactive mode is still running

  # Validates RIM-14, RIM-21: an action the demo file marks as not closing leaves the
  # notification presented; the later d proves the key reached the mode.
  @demo
  Scenario: An action that does not close keeps the notification
    Given the demo list starts open
    And interactive mode is running with demo file "keep-open.json"
    And the overlay is the frontmost application
    When I press "r"
    Then the notification titled "Pinned" is still presented
    And interactive mode is still running
    When I press "d"
    Then the notification titled "Pinned" is no longer presented

  # Validates RIM-14: Space performs Activate and the mode stays.
  @demo
  Scenario: Pressing Space activates the selected notification
    Given the demo list starts open
    And interactive mode is running with demo file "three.json"
    And the overlay is the frontmost application
    When I press "Space"
    Then the notification titled "First" is no longer presented
    And interactive mode is still running

  # Validates RIM-20, RIM-16: X clears everything presented, which empties the list.
  @demo
  Scenario: Pressing X clears every notification and ends the mode
    Given the demo list starts open
    And interactive mode is running with demo file "three.json"
    And the overlay is the frontmost application
    When I press "X"
    Then the overlay shows the label "No more jobs!"
    And interactive mode exits with status 0
    And no overlay window is present

  # Validates RIM-20, RIM-15: D dismisses the selected notification's app only; the selection
  # lands on what is now topmost.
  @demo
  Scenario: Pressing D dismisses the selected notification's app only
    Given the demo list starts open
    And interactive mode is running with demo file "two-apps.json"
    And the overlay is the frontmost application
    When I press "D"
    Then the notifications titled "Inbox one" and "Inbox two" are no longer presented
    And the notification titled "Meeting" is still presented
    And the topmost notification is selected
    And interactive mode is still running

  # Validates RIM-10: Close is performed by Dismiss, so it is not a separate entry.
  @demo
  Scenario: Close is not listed as an entry
    Given the demo list starts open
    And interactive mode is running with demo file "close-action.json"
    Then the selected panel shows activator "space" before "Activate"
    And the selected panel shows activator "d / D / X" before "Dismiss this / app / all"
    And the selected panel shows activator "a" before "Archive"
    And the selected panel does not list "Close"

  # Validates RIM-18: a collapsed stack offers Expand in place of Activate, on the same key.
  @demo
  Scenario: A collapsed stack offers Expand instead of Activate
    Given the demo list starts open
    And interactive mode is running with demo file "stack.json"
    Then the selected panel shows activator "space" before "Expand"
    And the selected panel shows activator "d / D / X" before "Dismiss this / app / all"
    And exactly one action panel is present

  # Validates RIM-18, RIM-15: Space expands the stack in place; the selection stays at its position,
  # now holding the first member.
  @demo
  Scenario: Expanding a stack presents its members in its place
    Given the demo list starts open
    And interactive mode is running with demo file "stack.json"
    And the overlay is the frontmost application
    When I press "Space"
    Then the notification titled "Inbox one" is still presented
    And the notification titled "Inbox two" is still presented
    And the notification titled "Meeting" is still presented
    And exactly one action panel is present
    And the topmost notification is selected
    And the selected panel shows activator "space" before "Activate"
    And interactive mode is still running

  # Validates RIM-22, RIM-21: a notification arrives above the selected one; the selection stays
  # on the same notification, now one position lower.
  @demo
  Scenario: An arriving notification leaves the selection on the same notification
    Given the demo list starts open
    And interactive mode is running with demo file "arrival.json"
    And the overlay is the frontmost application
    When I press "j"
    Then the notification at position 2 is selected
    And the notification titled "Late" becomes presented
    And exactly one action panel is present
    And the notification at position 3 is selected
    And the selected panel shows activator "s" before "Snooze"
    And interactive mode is still running

  # Validates RIM-22, RIM-21: a notification above the selected one leaves; the selection stays
  # on the same notification, now at the top.
  @demo
  Scenario: A departing notification leaves the selection on the same notification
    Given the demo list starts open
    And interactive mode is running with demo file "departure.json"
    And the overlay is the frontmost application
    When I press "j"
    Then the notification at position 2 is selected
    And the notification titled "First" is no longer presented
    And exactly one action panel is present
    And the topmost notification is selected
    And the selected panel shows activator "s" before "Snooze"
    And interactive mode is still running

  # Validates RIM-28: with no demo application running, --demo is refused before any window
  # appears.
  @demo
  Scenario: No running demo application is refused before the overlay appears
    When I run "nbk interactive --demo"
    Then the command fails
    And the error output starts with "nbk: --demo: no demo-nc process is running"
    And no overlay window is present

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
