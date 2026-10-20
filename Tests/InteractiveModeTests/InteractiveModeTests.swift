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
    func expand(index: Int) throws { touched = true }
    func perform(action displayName: String, index: Int) throws { touched = true }
    func clearAll() throws { touched = true }
    func clearAll(forApp index: Int) throws { touched = true }
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
        case expand(Int)
        case perform(String, Int)
        case clearAll
        case clearAllForApp(Int)
        case setPanelOpen(Bool)
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var presentedReads = 0
    private var readGates: [DispatchSemaphore] = []
    private let presented: [PresentedNotification]
    private let dismissError: Error?

    init(presented: [PresentedNotification] = [], dismissError: Error? = nil) {
        self.presented = presented
        self.dismissError = dismissError
    }

    var calls: [Call] { lock.withLock { recorded } }
    var readPresentedCount: Int { lock.withLock { presentedReads } }

    var onCall: (@Sendable (Call) -> Void)?

    private func record(_ call: Call) {
        lock.withLock { recorded.append(call) }
        onCall?(call)
    }

    var isTrusted: Bool { true }
    var isPanelOpen: Bool { true }
    func notificationCenterPID() -> pid_t? { nil }
    func read(wait: TimeInterval) throws -> [NotificationItem] { presented.map(\.item) }
    func readPresented() throws -> [PresentedNotification] {
        let gate = lock.withLock { () -> DispatchSemaphore? in
            presentedReads += 1
            return readGates.isEmpty ? nil : readGates.removeFirst()
        }
        gate?.wait()
        return presented
    }

    func holdNextRead() -> DispatchSemaphore {
        let gate = DispatchSemaphore(value: 0)
        lock.withLock { readGates.append(gate) }
        return gate
    }
    func dismiss(index: Int) throws {
        record(.dismiss(index))
        if let dismissError { throw dismissError }
    }
    func press(index: Int) throws { record(.press(index)) }
    func expand(index: Int) throws { record(.expand(index)) }
    func perform(action displayName: String, index: Int) throws {
        record(.perform(displayName, index))
    }
    func clearAll() throws { record(.clearAll) }
    func clearAll(forApp index: Int) throws { record(.clearAllForApp(index)) }
    func setPanelOpen(_ open: Bool) throws { record(.setPanelOpen(open)) }
}

@MainActor @Suite struct SessionReleaseScreenTests {
    /// RIM-6: the panel is closed exactly once however often the screen is released.
    @Test func releaseScreenClosesThePanelOnce() async throws {
        let access = RecordingAccess()
        let session = Session(access: access)
        session.releaseScreen()
        session.releaseScreen()
        try await Task.sleep(for: .milliseconds(100))
        #expect(access.calls == [.setPanelOpen(false)])
    }

    /// The overlay is hidden before the panel is closed, never the other way round.
    @Test func releaseScreenClosesThePanelOnlyAfterTheCurrentPass() async throws {
        let access = RecordingAccess()
        let session = Session(access: access)
        session.releaseScreen()
        #expect(access.calls.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(access.calls == [.setPanelOpen(false)])
    }
}

private final class PanelLog: @unchecked Sendable {
    enum Event: Equatable {
        case drawn
        case hidden
    }

    private let lock = NSLock()
    private var recorded: [Event] = []

    var events: [Event] { lock.withLock { recorded } }

    func record(_ spec: ActionPanelSpec?) {
        lock.withLock { recorded.append(spec == nil ? .hidden : .drawn) }
    }
}

@MainActor @Suite struct SessionKeyDispatchTests {
    private static let scriptEditorActions = ["Show Details", "Show", "Close"]

    private static func presented(_ indices: Int...) -> [PresentedNotification] {
        presented(indices)
    }

    private static func presented(_ indices: [Int]) -> [PresentedNotification] {
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
        let session = Session(access: access, dispatchQueue: queue, terminate: {})
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

    private func dismissedAfterRedraw(drawn: [Int], selecting moves: Int, redrawn: [Int])
        -> [RecordingAccess.Call]
    {
        let first = Self.presented(drawn)
        let access = RecordingAccess(presented: first)
        let (session, queue) = session(access, presented: first)
        for _ in 0..<moves { session.handle(.character("j")) }
        session.drawActionPanels(Self.presented(redrawn))
        session.handle(.character("d"))
        queue.sync {}
        return access.calls
    }

    @Test func redrawWithAnArrivalAboveKeepsTheSelectionOnTheSameNotification() {
        #expect(
            dismissedAfterRedraw(drawn: [1, 2], selecting: 1, redrawn: [0, 1, 2]) == [.dismiss(2)])
    }

    @Test func redrawWithTheAboveNotificationGoneKeepsTheSelectionOnTheSameNotification() {
        #expect(dismissedAfterRedraw(drawn: [1, 2], selecting: 1, redrawn: [2]) == [.dismiss(2)])
    }

    @Test func redrawWithTheSelectedNotificationGoneSelectsByPosition() {
        #expect(dismissedAfterRedraw(drawn: [1, 2], selecting: 1, redrawn: [1]) == [.dismiss(1)])
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

    private static func stack(_ index: Int) -> [PresentedNotification] {
        [
            PresentedNotification(
                item: NotificationItem(
                    index: index, app: "Script Editor", title: "Stack",
                    actions: ["Clear All", "Show"], isCollapsedStack: true),
                frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        ]
    }

    /// RIM-18: Space on a collapsed stack expands it instead of pressing.
    @Test func spaceOnACollapsedStackExpandsIt() {
        let presented = Self.stack(5)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character(" "))
        queue.sync {}
        #expect(access.calls == [.expand(5)])
    }

    /// RIM-18: d on a collapsed stack dismisses it as a whole.
    @Test func dKeyOnACollapsedStackDismissesIt() {
        let presented = Self.stack(5)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("d"))
        queue.sync {}
        #expect(access.calls == [.dismiss(5)])
    }

    /// RIM-18: a collapsed stack's panel offers Expand.
    @Test func collapsedStackPanelCarriesExpand() {
        let panel = ActionPanelLayout.panel(for: Self.stack(5), selectedIndex: 0)
        #expect(panel?.entries == ["Expand", "Dismiss", "Show"])
    }

    /// RIM-14: a named action's key performs that action.
    @Test func actionKeyPerformsTheNamedAction() {
        let presented = Self.presented(2)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("s"))
        queue.sync {}
        #expect(access.calls == [.perform("Show Details", 2)])
    }

    /// A second key while an entry is still being performed is dropped, not queued.
    @Test func keysWhileDispatchingAreIgnored() {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("d"))
        session.handle(.character("d"))
        session.handle(.character("s"))
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
            session.handle(.character("s"))
            queue.sync {}
        }
        #expect(access.calls == [.dismiss(1), .perform("Show Details", 1)])
    }

    private func loggedSession(
        _ access: RecordingAccess, presented: [PresentedNotification]
    ) -> (Session, DispatchQueue, PanelLog) {
        let queue = DispatchQueue(label: "dispatch-test")
        let session = Session(access: access, dispatchQueue: queue, terminate: {})
        let log = PanelLog()
        session.panelDecorator = { log.record($0) }
        session.drawActionPanels(presented)
        return (session, queue, log)
    }

    /// RIM-24: the panel is gone before the entry is performed.
    @Test func dKeyHidesThePanelBeforeTheEntryIsPerformed() {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue, log) = loggedSession(access, presented: presented)
        nonisolated(unsafe) var seenAtDismiss: [PanelLog.Event] = []
        access.onCall = { if $0 == .dismiss(1) { seenAtDismiss = log.events } }
        session.handle(.character("d"))
        queue.sync {}
        #expect(seenAtDismiss == [.drawn, .hidden])
    }

    /// RIM-24: the panel is redrawn after the entry even when the list is unchanged.
    @Test func panelIsRedrawnAfterAnEntryThatLeavesTheListUnchanged() async throws {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue, log) = loggedSession(access, presented: presented)
        session.handle(.character("d"))
        queue.sync {}
        try await waitUntil { log.events.last == .drawn && log.events.count == 3 }
        #expect(log.events == [.drawn, .hidden, .drawn])
    }

    /// RIM-24: Expand keeps the panel.
    @Test func spaceOnACollapsedStackNeverHidesThePanel() async throws {
        let presented = Self.stack(5)
        let access = RecordingAccess(presented: presented)
        let (session, queue, log) = loggedSession(access, presented: presented)
        session.handle(.character(" "))
        queue.sync {}
        try await waitUntil { access.readPresentedCount >= 1 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!log.events.contains(.hidden))
    }

    /// RIM-24: Activate on a notification that is not a stack hides the panel.
    @Test func spaceOnANotificationHidesThePanelBeforeActivating() {
        let presented = Self.presented(4)
        let access = RecordingAccess(presented: presented)
        let (session, queue, log) = loggedSession(access, presented: presented)
        nonisolated(unsafe) var seenAtPress: [PanelLog.Event] = []
        access.onCall = { if $0 == .press(4) { seenAtPress = log.events } }
        session.handle(.character(" "))
        queue.sync {}
        #expect(seenAtPress == [.drawn, .hidden])
    }

    /// RIM-24: a named action hides the panel before it is performed.
    @Test func actionKeyHidesThePanelBeforeTheEntryIsPerformed() {
        let presented = Self.presented(2)
        let access = RecordingAccess(presented: presented)
        let (session, queue, log) = loggedSession(access, presented: presented)
        nonisolated(unsafe) var seen: [PanelLog.Event] = []
        access.onCall = { if $0 == .perform("Show Details", 2) { seen = log.events } }
        session.handle(.character("s"))
        queue.sync {}
        #expect(seen == [.drawn, .hidden])
    }

    /// RIM-24: X and D hide the panel before they are performed.
    @Test func upperCaseKeysHideThePanelBeforeTheyArePerformed() {
        for (key, call) in [("X", RecordingAccess.Call.clearAll), ("D", .clearAllForApp(3))] {
            let presented = Self.presented(3, 7)
            let access = RecordingAccess(presented: presented)
            let (session, queue, log) = loggedSession(access, presented: presented)
            nonisolated(unsafe) var seen: [PanelLog.Event] = []
            access.onCall = { if $0 == call { seen = log.events } }
            session.handle(.character(key))
            queue.sync {}
            #expect(seen == [.drawn, .hidden])
        }
    }

    /// RIM-24: a periodic refresh landing mid-entry cannot bring the panel back.
    @Test func refreshWhileAnEntryIsInFlightDoesNotDrawThePanel() async throws {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue, log) = loggedSession(access, presented: presented)
        queue.suspend()
        session.handle(.character("d"))
        session.showActionPanels()
        try await waitUntil { access.readPresentedCount >= 2 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(log.events == [.drawn, .hidden])
        queue.resume()
        queue.sync {}
    }

    /// RIM-24: a periodic read issued before the entry finished is dropped, not drawn.
    @Test func readIssuedBeforeTheEntryFinishedDoesNotResurrectThePanel() async throws {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue, log) = loggedSession(access, presented: presented)
        let stale = access.holdNextRead()
        let fresh = access.holdNextRead()
        session.scheduleRead()
        try await waitUntil { access.readPresentedCount >= 1 }
        session.handle(.character("d"))
        queue.sync {}
        try await waitUntil { access.readPresentedCount >= 2 }
        stale.signal()
        try await Task.sleep(for: .milliseconds(100))
        #expect(log.events == [.drawn, .hidden])
        fresh.signal()
        try await waitUntil { log.events.count == 3 }
        #expect(log.events == [.drawn, .hidden, .drawn])
    }

    /// RIM-24: keys between the entry finishing and the redraw are dropped.
    @Test func keysBeforeThePanelIsRedrawnAreIgnored() async throws {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue, log) = loggedSession(access, presented: presented)
        let fresh = access.holdNextRead()
        session.handle(.character("d"))
        queue.sync {}
        try await waitUntil { access.readPresentedCount >= 1 }
        session.handle(.character("d"))
        session.handle(.character("X"))
        queue.sync {}
        #expect(access.calls == [.dismiss(1)])
        fresh.signal()
        try await waitUntil { log.events.count == 3 }
        session.handle(.character("s"))
        queue.sync {}
        #expect(access.calls == [.dismiss(1), .perform("Show Details", 1)])
    }

    /// RIM-24: moving the selection while the panel is hidden does not draw it.
    @Test func selectionMovesWhileAnEntryIsInFlightDoNotRedrawThePanel() {
        let presented = Self.presented(1, 2)
        let access = RecordingAccess(presented: presented)
        let (session, queue, log) = loggedSession(access, presented: presented)
        queue.suspend()
        session.handle(.character("d"))
        session.handle(.down)
        #expect(log.events == [.drawn, .hidden])
        queue.resume()
        queue.sync {}
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
            session.handle(.character("s"))
            queue.sync {}
            return access.calls.count >= 2
        }
        #expect(access.calls == [.dismiss(5), .perform("Show Details", 5)])
    }

    @Test func eachEntryIsFollowedByExactlyOneImmediateRead() async throws {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue, log) = loggedSession(access, presented: presented)
        for expected in 1...3 {
            session.handle(.character("s"))
            queue.sync {}
            try await waitUntil { access.readPresentedCount >= expected }
            try await waitUntil { log.events.last == .drawn }
            #expect(access.readPresentedCount == expected)
        }
        try await Task.sleep(for: .milliseconds(1200))
        #expect(access.readPresentedCount == 3)
    }

    @Test func xKeyClearsAll() {
        let presented = Self.presented(3, 7)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("X"))
        queue.sync {}
        #expect(access.calls == [.clearAll])
    }

    @Test func dKeyDismissesAllForTheSelectedApp() {
        let presented = Self.presented(3, 7)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("j"))
        session.handle(.character("D"))
        queue.sync {}
        #expect(access.calls == [.clearAllForApp(7)])
    }

    @Test func dKeyWithNothingPresentedPerformsNothing() {
        let access = RecordingAccess()
        let (session, queue) = session(access, presented: [])
        session.handle(.character("D"))
        queue.sync {}
        #expect(access.calls.isEmpty)
    }

    @Test func globalKeyWhileDispatchingIsIgnored() {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        session.handle(.character("d"))
        session.handle(.character("X"))
        queue.sync {}
        #expect(access.calls == [.dismiss(1)])
    }

    @Test func globalKeysAreFollowedByExactlyOneImmediateRead() async throws {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, queue) = session(access, presented: presented)
        for (expected, key) in ["X", "D"].enumerated() {
            session.handle(.character(key))
            queue.sync {}
            try await waitUntil { access.readPresentedCount >= expected + 1 }
            #expect(access.readPresentedCount == expected + 1)
        }
        try await Task.sleep(for: .milliseconds(1200))
        #expect(access.readPresentedCount == 2)
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
        for key in ["x", "C", "z"] { session.handle(.character(key)) }
        queue.sync {}
        #expect(access.calls.isEmpty)
    }
}

@MainActor @Suite struct SessionEndingTests {
    private final class Terminations {
        var count = 0
    }

    private static func presented(_ indices: Int...) -> [PresentedNotification] {
        presented(indices)
    }

    private static func presented(_ indices: [Int]) -> [PresentedNotification] {
        indices.enumerated().map { offset, index in
            PresentedNotification(
                item: NotificationItem(
                    index: index, app: "Script Editor", title: "N\(index)",
                    actions: ["Show Details"]),
                frame: CGRect(x: 0, y: CGFloat(offset) * 100, width: 300, height: 80))
        }
    }

    private func session(
        _ access: RecordingAccess, hold: TimeInterval = 0, queue: DispatchQueue = .main
    ) -> (Session, Terminations) {
        let terminations = Terminations()
        let session = Session(
            access: access, dispatchQueue: queue, endingHold: hold, endingFade: 0,
            terminate: { terminations.count += 1 })
        return (session, terminations)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// RIM-16: nothing presented ends the mode with the panel closed.
    @Test func emptyPresentedSetEndsTheModeWithThePanelClosed() async throws {
        let access = RecordingAccess()
        let (session, terminations) = session(access)
        session.drawActionPanels([])
        try await waitUntil { terminations.count > 0 }
        #expect(terminations.count == 1)
        #expect(access.calls == [.setPanelOpen(false)])
    }

    @Test func nonEmptyPresentedSetKeepsTheModeRunning() async throws {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let (session, terminations) = session(access)
        session.drawActionPanels(presented)
        try await Task.sleep(for: .milliseconds(200))
        #expect(terminations.count == 0)
        #expect(access.calls.isEmpty)
    }

    /// RIM-16: movement and activator keys do nothing while the label shows.
    @Test func movementAndActivatorKeysDoNothingWhileEnding() {
        let presented = Self.presented(1, 2)
        let access = RecordingAccess(presented: presented)
        let queue = DispatchQueue(label: "ending-test")
        let (session, terminations) = session(access, hold: 60, queue: queue)
        var decorated: [[PresentedNotification]] = []
        session.presentedDecorator = { decorated.append($0) }
        session.drawActionPanels([])
        session.drawActionPanels(presented)
        for key: OverlayKey in [.character("j"), .down, .character("d"), .character(" ")] {
            session.handle(key)
        }
        queue.sync {}
        #expect(access.calls.isEmpty)
        #expect(decorated == [[], presented])
        #expect(terminations.count == 0)
    }

    @Test func globalKeysDoNothingWhileEnding() {
        let presented = Self.presented(1)
        let access = RecordingAccess(presented: presented)
        let queue = DispatchQueue(label: "ending-global-test")
        let (session, terminations) = session(access, hold: 60, queue: queue)
        session.drawActionPanels([])
        session.drawActionPanels(presented)
        for key in ["X", "D"] { session.handle(.character(key)) }
        queue.sync {}
        #expect(access.calls.isEmpty)
        #expect(terminations.count == 0)
    }

    /// RIM-16: Escape while the label shows ends the mode at once.
    @Test func escapeWhileEndingEndsTheModeAtOnce() async throws {
        let access = RecordingAccess()
        let (session, terminations) = session(access, hold: 60)
        session.drawActionPanels([])
        session.handle(.escape)
        try await waitUntil { terminations.count > 0 }
        #expect(terminations.count == 1)
        #expect(access.calls == [.setPanelOpen(false)])
    }

    /// RIM-16: a signal during the label ends the mode once; the fade does not end it again.
    @Test func teardownDuringEndingTerminatesOnce() async throws {
        let access = RecordingAccess()
        let (session, terminations) = session(access)
        session.drawActionPanels([])
        session.teardown()
        try await Task.sleep(for: .milliseconds(200))
        #expect(terminations.count == 1)
        #expect(access.calls == [.setPanelOpen(false)])
    }

    /// RIM-16: Escape followed by a signal ends the mode once.
    @Test func escapeThenSignalTerminatesOnce() async throws {
        let access = RecordingAccess()
        let (session, terminations) = session(access, hold: 60)
        session.drawActionPanels([])
        session.handle(.escape)
        session.teardown()
        try await waitUntil { terminations.count > 0 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(terminations.count == 1)
        #expect(access.calls == [.setPanelOpen(false)])
    }

    @Test func repeatedEmptyDrawsTerminateOnce() async throws {
        let access = RecordingAccess()
        let (session, terminations) = session(access)
        session.drawActionPanels([])
        session.drawActionPanels([])
        try await waitUntil { terminations.count > 0 }
        try await Task.sleep(for: .milliseconds(200))
        #expect(terminations.count == 1)
    }
}

@MainActor @Suite struct SessionDecoratorTests {
    private static func presented(atTops tops: CGFloat...) -> [PresentedNotification] {
        tops.enumerated().map { index, top in
            PresentedNotification(
                item: NotificationItem(index: index, title: "N\(index)", actions: []),
                frame: CGRect(x: 0, y: top, width: 300, height: 80))
        }
    }

    private final class Recorder {
        var calls: [[PresentedNotification]] = []
    }

    private func session(_ access: RecordingAccess) -> (Session, Recorder) {
        let recorder = Recorder()
        let session = Session(access: access, terminate: {})
        session.presentedDecorator = { recorder.calls.append($0) }
        return (session, recorder)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func readPresentedReachesTheDecoratorTopDown() async throws {
        let bottomUp = Self.presented(atTops: 200, 100)
        let (session, recorder) = session(RecordingAccess(presented: bottomUp))
        session.showActionPanels()
        try await waitUntil { !recorder.calls.isEmpty }
        #expect(recorder.calls == [PresentedNotification.topDown(bottomUp)])
        #expect(recorder.calls.first?.map(\.item.index) == [1, 0])
    }

    @Test func aSelectionMoveRedecorates() {
        let presented = Self.presented(atTops: 0, 100)
        let (session, recorder) = session(RecordingAccess(presented: presented))
        session.drawActionPanels(presented)
        session.handle(.character("j"))
        #expect(recorder.calls == [presented, presented])
    }

    @Test func anEmptyFirstReadStillDecoratesOnce() async throws {
        let (session, recorder) = session(RecordingAccess(presented: []))
        session.showActionPanels()
        try await waitUntil { !recorder.calls.isEmpty }
        #expect(recorder.calls == [[]])
        try await Task.sleep(for: .milliseconds(1200))
        #expect(recorder.calls == [[]])
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

@Suite struct SettledPresentedTests {
    private static let interval: TimeInterval = 0.15
    private static let cap: TimeInterval = 1

    private static let one = [
        PresentedNotification(
            item: NotificationItem(index: 0, app: "Script Editor", title: "N0", actions: []),
            frame: CGRect(x: 0, y: 0, width: 300, height: 80))
    ]

    private final class Script {
        let reads: [(ready: Bool, presented: [PresentedNotification])]
        private(set) var count = 0
        private(set) var elapsed: TimeInterval = 0
        init(_ reads: [(ready: Bool, presented: [PresentedNotification])]) { self.reads = reads }

        func isReady() -> Bool { reads[min(count, reads.count - 1)].ready }
        func read() -> [PresentedNotification] {
            defer { count += 1 }
            return reads[min(count, reads.count - 1)].presented
        }
        func now() -> Date { Date(timeIntervalSince1970: elapsed) }
        func sleep(_ seconds: TimeInterval) { elapsed += seconds }
    }

    private static func settle(_ script: Script) -> [PresentedNotification] {
        Session.settledPresented(
            read: script.read, isReady: script.isReady, emptyAgreement: 2,
            deadline: Date(timeIntervalSince1970: cap), interval: interval,
            now: script.now, sleep: script.sleep)
    }

    @Test func emptyReadsBeforeReadyDoNotSettle() {
        let script = Script([(false, []), (false, []), (false, []), (true, []), (true, [])])
        #expect(Self.settle(script).isEmpty)
        #expect(script.count == 5)
    }

    @Test func settlesOnTheSecondReadyEmptyRead() {
        let script = Script([(true, []), (true, []), (true, []), (true, [])])
        #expect(Self.settle(script).isEmpty)
        #expect(script.count == 2)
    }

    @Test func aRowAppearingAfterAReadyEmptyReadWins() {
        let script = Script([(true, []), (true, Self.one), (true, Self.one), (true, [])])
        #expect(Self.settle(script) == Self.one)
        #expect(script.count == 3)
    }

    @Test func readyEmptyReadsMustBeConsecutive() {
        let script = Script([(true, []), (true, Self.one), (true, []), (true, []), (true, [])])
        #expect(Self.settle(script).isEmpty)
        #expect(script.count == 4)
    }

    @Test func readinessDroppingResetsTheEmptyCount() {
        let script = Script([(true, []), (false, []), (true, []), (true, []), (true, [])])
        #expect(Self.settle(script).isEmpty)
        #expect(script.count == 4)
    }

    @Test func neverReadyStopsAtTheCap() {
        let script = Script([(false, [])])
        #expect(Self.settle(script).isEmpty)
        #expect(script.count == Int((Self.cap / Self.interval).rounded(.up)) + 1)
    }
}

@Suite struct GlassOutlineShapeTests {
    @available(macOS 26, *)
    private func shape(halo: CGRect, panel: CGRect) -> GlassOutlineShape {
        GlassOutlineShape(halo: halo, panel: panel, haloRadius: 12, panelRadius: 8, fillet: 6)
    }

    @available(macOS 26, *)
    @Test func animatableDataMidpointYieldsMidpointRects() {
        let from = shape(
            halo: CGRect(x: 0, y: 0, width: 100, height: 40),
            panel: CGRect(x: 0, y: 0, width: 60, height: 80))
        let to = shape(
            halo: CGRect(x: 20, y: 10, width: 140, height: 60),
            panel: CGRect(x: 20, y: 10, width: 100, height: 120))
        var mid = from
        var delta = to.animatableData
        delta -= from.animatableData
        delta.scale(by: 0.5)
        mid.animatableData = from.animatableData + delta
        #expect(mid.halo == CGRect(x: 10, y: 5, width: 120, height: 50))
        #expect(mid.panel == CGRect(x: 10, y: 5, width: 80, height: 100))
    }
}

@Suite struct ActionPanelsWindowDurationTests {
    @Test func durationIsKeptWithoutReduceMotion() {
        #expect(
            ActionPanelsWindow.duration(ActionPanelsWindow.move, reduceMotion: false)
                == ActionPanelsWindow.move)
    }

    @Test func reduceMotionMakesEveryDurationZero() {
        #expect(ActionPanelsWindow.duration(ActionPanelsWindow.move, reduceMotion: true) == 0)
        #expect(ActionPanelsWindow.duration(ActionPanelsWindow.fade, reduceMotion: true) == 0)
    }
}

@Suite struct PanelVisibilityTests {
    @Test func firstShowReportsItWasHidden() {
        var visibility = PanelVisibility()
        #expect(visibility.show() == false)
        #expect(visibility.show() == true)
    }

    @Test func hidingWhileHiddenStartsNoFade() {
        var visibility = PanelVisibility()
        #expect(visibility.hide() == nil)
    }

    @Test func aHideIsStillInForceUntilTheNextShow() throws {
        var visibility = PanelVisibility()
        _ = visibility.show()
        let pending = visibility.hide()
        let hide = try #require(pending)
        #expect(visibility.isStillHidden(since: hide))
    }

    @Test func aShowDuringTheFadeOutCancelsTheRemoval() throws {
        var visibility = PanelVisibility()
        _ = visibility.show()
        let pending = visibility.hide()
        let hide = try #require(pending)
        #expect(visibility.show() == false)
        #expect(!visibility.isStillHidden(since: hide))
    }

    @Test func onlyTheLatestHideRemoves() throws {
        var visibility = PanelVisibility()
        _ = visibility.show()
        let firstPending = visibility.hide()
        let first = try #require(firstPending)
        _ = visibility.show()
        let secondPending = visibility.hide()
        let second = try #require(secondPending)
        #expect(!visibility.isStillHidden(since: first))
        #expect(visibility.isStillHidden(since: second))
    }
}
