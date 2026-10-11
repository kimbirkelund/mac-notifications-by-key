import AppKit
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
    func readPresented() throws -> [PresentedNotification] {
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

private final class RecordingAccess: NotificationCenterAccess, @unchecked Sendable {
    enum Call: Equatable {
        case dismiss(Int)
        case press(Int)
        case perform(String, Int)
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var presentedReads = 0
    private let presented: [PresentedNotification]
    private let dismissError: Error?

    init(presented: [PresentedNotification] = [], dismissError: Error? = nil) {
        self.presented = presented
        self.dismissError = dismissError
    }

    var calls: [Call] { lock.withLock { recorded } }
    var readPresentedCount: Int { lock.withLock { presentedReads } }

    private func record(_ call: Call) { lock.withLock { recorded.append(call) } }

    var isTrusted: Bool { true }
    var isPanelOpen: Bool { true }
    func notificationCenterPID() -> pid_t? { nil }
    func read(wait: TimeInterval) throws -> [NotificationItem] { presented.map(\.item) }
    func readPresented() throws -> [PresentedNotification] {
        lock.withLock { presentedReads += 1 }
        return presented
    }
    func dismiss(index: Int) throws {
        record(.dismiss(index))
        if let dismissError { throw dismissError }
    }
    func press(index: Int) throws { record(.press(index)) }
    func perform(action displayName: String, index: Int) throws {
        record(.perform(displayName, index))
    }
    func setPanelOpen(_ open: Bool) throws {}
}

@MainActor @Suite struct SessionKeyDispatchTests {
    private static let scriptEditorActions = ["Show Details", "Show", "Close"]

    private static func presented(_ indices: Int...) -> [PresentedNotification] {
        indices.enumerated().map { offset, index in
            PresentedNotification(
                item: NotificationItem(
                    index: index, app: "Script Editor", title: "N\(index)",
                    actions: scriptEditorActions),
                frame: CGRect(x: 0, y: CGFloat(offset) * 100, width: 300, height: 80))
        }
    }

    private func session(
        _ access: RecordingAccess, presented: [PresentedNotification]
    ) -> (Session, DispatchQueue) {
        let queue = DispatchQueue(label: "dispatch-test")
        let session = Session(access: access, dispatchQueue: queue)
        session.drawActionPanels(presented)
        return (session, queue)
    }

    /// RIM-14: d dismisses the selected notification by its list index.
    @Test func dKeyDismissesTheSelectedNotification() {
        let presented = Self.presented(3, 7)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("j"))
        session.handle(.character("d"))
        queue.sync {}
        #expect(access.calls == [.dismiss(7)])
    }

    /// RIM-14: Space performs the default activation.
    @Test func spaceActivatesTheSelectedNotification() {
        let presented = Self.presented(4)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character(" "))
        queue.sync {}
        #expect(access.calls == [.press(4)])
    }

    /// RIM-14: a named action's key performs that action.
    @Test func actionKeyPerformsTheNamedAction() {
        let presented = Self.presented(2)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("c"))
        queue.sync {}
        #expect(access.calls == [.perform("Close", 2)])
    }

    /// A second key while an entry is still being performed is dropped, not queued.
    @Test func keysWhileDispatchingAreIgnored() {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("d"))
        session.handle(.character("d"))
        session.handle(.character("c"))
        queue.sync {}
        #expect(access.calls == [.dismiss(1)])
    }

    @Test func keysDispatchAgainOnceThePreviousEntryFinished() async throws {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("d"))
        queue.sync {}
        let deadline = Date().addingTimeInterval(2)
        while access.calls.count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
            session.handle(.character("c"))
            queue.sync {}
        }
        #expect(access.calls == [.dismiss(1), .perform("Close", 1)])
    }

    private func waitUntil(
        timeout: TimeInterval = 2, _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// RIM-14: a failed entry is reported, never fatal; the mode keeps taking keys.
    @Test func failedEntryLeavesTheModeTakingKeys() async throws {
        let presented = Self.presented(5)
        let access = RecordingAccess(
            presented: presented,
            dismissError: NbkError.indexOutOfRange(requested: 5, count: 0))
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("d"))
        queue.sync {}
        try await waitUntil {
            session.handle(.character("c"))
            queue.sync {}
            return access.calls.count >= 2
        }
        #expect(access.calls == [.dismiss(5), .perform("Close", 5)])
    }

    @Test func eachEntryIsFollowedByExactlyOneImmediateRead() async throws {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        for expected in 1...3 {
            session.handle(.character("c"))
            queue.sync {}
            try await waitUntil { access.readPresentedCount >= expected }
            #expect(access.readPresentedCount == expected)
        }
        try await Task.sleep(for: .milliseconds(1200))
        #expect(access.readPresentedCount == 3)
    }

    @Test func noSelectionPerformsNothing() {
        let access = RecordingAccess()
        let (session, queue) = session(access, presented: [])
        for key in ["d", " ", "c"] { session.handle(.character(key)) }
        queue.sync {}
        #expect(access.calls.isEmpty)
    }

    /// RIM-17: keys not shown in the selected panel perform nothing.
    @Test func unboundKeysPerformNothing() {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        for key in ["x", "D", "C"] { session.handle(.character(key)) }
        queue.sync {}
        #expect(access.calls.isEmpty)
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

@Suite struct ScreenGeometryTests {
    /// RIM-10: panels are laid out in top-left-origin screen coordinates and drawn in AppKit's.
    @Test func flipsTopLeftOriginRectIntoBottomLeftOrigin() {
        let cg = CGRect(x: 100, y: 50, width: 160, height: 80)
        #expect(
            ScreenGeometry.appKitRect(fromCG: cg, primaryScreenHeight: 1000)
                == CGRect(x: 100, y: 870, width: 160, height: 80))
    }

    @Test func localRectIsRelativeToTheWindowOrigin() {
        let rect = CGRect(x: 1540, y: 870, width: 160, height: 80)
        let window = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        #expect(
            ScreenGeometry.local(rect, in: window) == CGRect(x: 100, y: 870, width: 160, height: 80)
        )
    }
}

@Suite struct OverlayKeyTests {
    private func key(
        _ keyCode: UInt16, _ characters: String?, _ modifiers: NSEvent.ModifierFlags = []
    ) -> OverlayKey? {
        OverlayKey(keyCode: keyCode, characters: characters, modifiers: modifiers)
    }

    @Test func mapsEscapeAndArrowsByKeyCode() {
        #expect(key(53, "\u{1b}") == .escape)
        #expect(key(126, "\u{f700}", [.numericPad, .function]) == .up)
        #expect(key(125, "\u{f701}", [.numericPad, .function]) == .down)
    }

    @Test func unshiftedLetterIsLowerCaseCharacter() {
        #expect(key(38, "j") == .character("j"))
    }

    /// RIM-17: a shifted letter maps to an upper-case character that nothing binds.
    @Test func shiftedLetterIsUpperCaseCharacter() {
        #expect(key(38, "j", .shift) == .character("J"))
    }

    @Test func spaceIsASpaceCharacter() {
        #expect(key(49, " ") == .character(" "))
    }

    /// RIM-17: Command, Option or Control chords are unbound, whatever the key.
    @Test func chordsWithCommandOptionOrControlAreUnmapped() {
        for modifier: NSEvent.ModifierFlags in [.command, .option, .control] {
            #expect(key(38, "j", modifier) == nil)
            #expect(key(125, "\u{f701}", [modifier, .function]) == nil)
            #expect(key(53, "\u{1b}", modifier) == nil)
        }
    }

    /// RIM-17: function keys report a private-use character and are ignored.
    @Test func functionKeysAreUnmapped() {
        #expect(key(122, "\u{f704}", .function) == nil)
        #expect(key(111, "\u{f70f}", .function) == nil)
    }

    @Test func keysWithoutASingleCharacterAreUnmapped() {
        #expect(key(0, nil) == nil)
        #expect(key(0, "") == nil)
    }
}

@Suite struct OverlayKeySelectionMoveTests {
    /// RIM-12: Down and j move down; Up and k move up.
    @Test func movementKeysMapToMoves() {
        #expect(OverlayKey.down.selectionMove == .down)
        #expect(OverlayKey.character("j").selectionMove == .down)
        #expect(OverlayKey.up.selectionMove == .up)
        #expect(OverlayKey.character("k").selectionMove == .up)
    }

    /// RIM-17: other keys, including shifted J/K, move nothing.
    @Test func otherKeysMapToNoMove() {
        for key: OverlayKey in [.escape, .character("x"), .character("J"), .character("K")] {
            #expect(key.selectionMove == nil)
        }
    }
}
