import CoreGraphics
import Foundation
import NotificationAX
import NotificationCore
import Testing

@testable import InteractiveMode

private final class UnusedAccess: NotificationCenterAccess {
    private(set) var touched = false
    var isTrusted: Bool {
        touched = true
        return true
    }
    var isPanelOpen: Bool {
        touched = true
        return false
    }
    func notificationCenterPID() -> pid_t? {
        touched = true
        return nil
    }
    func read(wait: TimeInterval) throws -> [NotificationItem] {
        touched = true
        return []
    }
    func dismiss(index: Int) throws { touched = true }
    func press(index: Int) throws { touched = true }
    func perform(action displayName: String, index: Int) throws { touched = true }
    func setPanelOpen(_ open: Bool) throws { touched = true }
}

@MainActor @Suite struct InteractiveSessionTests {
    /// RIM-8: no main screen is reported as an error, before any panel or lock side effect.
    @Test func throwsNoScreenWhenNoMainScreenExists() {
        let access = UnusedAccess()
        #expect(throws: InteractiveError.noScreen) {
            try InteractiveSession.run(access: access, mainScreenFrame: { nil })
        }
        #expect(!access.touched)
    }
}

@Suite struct InteractiveErrorTests {
    /// RIM-8: reported on stderr with a non-zero exit.
    @Test func noScreenHasMessageAndExitCodeOne() {
        #expect(!InteractiveError.noScreen.message.isEmpty)
        #expect(InteractiveError.noScreen.exitCode == 1)
    }
}

@Suite struct InstanceDecisionTests {
    @Test func acquiredLockRuns() {
        #expect(InstanceDecision(lockAcquired: true, ownerPID: nil) == .run)
        #expect(InstanceDecision(lockAcquired: true, ownerPID: 42) == .run)
    }

    /// RIM-4: a held lock focuses the owning instance instead of starting another.
    @Test func heldLockFocusesTheOwner() {
        #expect(InstanceDecision(lockAcquired: false, ownerPID: 42) == .focusExisting(42))
    }

    /// Owner pid not yet written (lock taken, pid pending): still never start a second overlay.
    @Test func heldLockWithUnknownOwnerDoesNotRun() {
        #expect(InstanceDecision(lockAcquired: false, ownerPID: nil) == .focusExisting(nil))
    }
}
