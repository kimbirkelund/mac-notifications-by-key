import Foundation
import Testing

@testable import DemoNotifications

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [DemoEvent] = []

    var events: [DemoEvent] { lock.withLock { all } }

    func record(_ event: DemoEvent) { lock.withLock { all.append(event) } }
}

private final class Clock: @unchecked Sendable {
    var current = Date(timeIntervalSince1970: 1_000)

    func advance(_ seconds: TimeInterval) { current.addTimeInterval(seconds) }
}

@Suite struct DemoEventTests {
    private static func observed(
        _ notifications: [DemoNotification], listOpen: Bool = false, clock: Clock = Clock()
    ) -> (DemoNotificationsModel, Recorder) {
        let model = DemoNotificationsModel(
            notifications: notifications, isListOpen: listOpen, now: { clock.current })
        let recorder = Recorder()
        model.observer = recorder.record
        return (model, recorder)
    }

    private static let reply = DemoNotification(
        title: "A",
        actions: [
            DemoAction(name: "Reply", closes: true, field: true),
            DemoAction(name: "Archive"),
            DemoAction(name: "Snooze", closes: false),
        ])

    @Test func stateDescribesPresentedNotificationsAndListOpen() {
        let (model, _) = Self.observed(
            [
                DemoNotification(
                    app: "Mail", title: "Inbox", subtitle: "s", body: "b",
                    actions: [DemoAction(name: "Archive")],
                    members: [DemoNotification(title: "One"), DemoNotification(title: "Two")]),
                DemoNotification(title: "B"),
            ], listOpen: true)
        #expect(
            model.state()
                == DemoState(
                    notifications: [
                        DemoNotificationState(
                            id: 0, app: "Mail", title: "Inbox", subtitle: "s", body: "b",
                            actions: ["Archive"], collapsedStack: true, hiddenMembers: 2),
                        DemoNotificationState(id: 1, title: "B"),
                    ], listOpen: true))
    }

    @Test func readyCarriesTheInitialState() throws {
        let (model, recorder) = Self.observed([DemoNotification(title: "A")])
        model.ready()
        let event = try #require(recorder.events.first)
        #expect(event.event == .ready)
        #expect(event.state == model.state())
        #expect(event.state.listOpen == false)
    }

    @Test func listOpenAndCloseEmitOnlyOnChange() {
        let (model, recorder) = Self.observed([])
        model.setListOpen(true)
        model.setListOpen(true)
        model.setListOpen(false)
        #expect(recorder.events.map(\.event) == [.listOpened, .listClosed])
        #expect(recorder.events.map(\.state.listOpen) == [true, false])
        #expect(model.isListOpen == false)
    }

    @Test func arrivalAndDepartureComeFromTheClock() throws {
        let clock = Clock()
        let (model, recorder) = Self.observed(
            [
                DemoNotification(title: "Now", leavesAfter: 2),
                DemoNotification(title: "Later", arrivesAfter: 1),
            ], clock: clock)
        model.advance()
        #expect(recorder.events.isEmpty)
        clock.advance(1)
        model.advance()
        clock.advance(1.5)
        model.advance()
        model.advance()
        #expect(recorder.events.map(\.event) == [.arrived, .departed])
        #expect(recorder.events.map(\.id) == [1, 0])
        #expect(recorder.events[0].state.notifications.map(\.title) == ["Now", "Later"])
        #expect(recorder.events[1].state.notifications.map(\.title) == ["Later"])
    }

    @Test func pressThatClosesIsApplied() throws {
        let (model, recorder) = Self.observed([DemoNotification(title: "A")])
        try model.press(id: 0)
        let event = try #require(recorder.events.first)
        #expect(event.event == .action)
        #expect(event.kind == .press)
        #expect(event.id == 0)
        #expect(event.outcome == .applied)
        #expect(event.state.notifications.isEmpty)
    }

    @Test func pressThatDoesNotCloseIsKept() throws {
        let (model, recorder) = Self.observed([
            DemoNotification(title: "A", activateCloses: false)
        ])
        try model.press(index: 0)
        let event = try #require(recorder.events.first)
        #expect(event.outcome == .kept)
        #expect(event.id == 0)
        #expect(event.state.notifications.map(\.title) == ["A"])
    }

    @Test func closeNamesTheTargetResolvedFromIndex() throws {
        let (model, recorder) = Self.observed([
            DemoNotification(title: "A"), DemoNotification(title: "B"),
        ])
        try model.dismiss(index: 1)
        let event = try #require(recorder.events.first)
        #expect(event.kind == .close)
        #expect(event.id == 1)
        #expect(event.outcome == .applied)
    }

    @Test func namedActionReportsItsNameAndOutcome() throws {
        let (model, recorder) = Self.observed([Self.reply, Self.reply])
        try model.perform(action: "Archive", id: 0)
        try model.perform(action: "Snooze", id: 1)
        try model.perform(action: "Reply", id: 1)
        let events = recorder.events
        #expect(events.map(\.kind) == [.named, .named, .named])
        #expect(events.map(\.action) == ["Archive", "Snooze", "Reply"])
        #expect(events.map(\.outcome) == [.applied, .kept, .kept])
        #expect(events[2].state.notifications.map(\.replyField) == [true])
    }

    @Test func expandIsApplied() throws {
        let (model, recorder) = Self.observed([
            DemoNotification(title: "Inbox", members: [DemoNotification(title: "One")])
        ])
        try model.expand(id: 0)
        let event = try #require(recorder.events.first)
        #expect(event.kind == .expand)
        #expect(event.id == 0)
        #expect(event.outcome == .applied)
        #expect(event.state.notifications.map(\.title) == ["One"])
    }

    @Test func clearAllIsApplied() throws {
        let (model, recorder) = Self.observed([
            DemoNotification(title: "A"), DemoNotification(title: "B"),
        ])
        model.clearAll()
        let event = try #require(recorder.events.first)
        #expect(event.kind == .clearAll)
        #expect(event.id == nil)
        #expect(event.outcome == .applied)
        #expect(event.state.notifications.isEmpty)
    }

    @Test func submitFieldReportsTheTypedText() throws {
        let (model, recorder) = Self.observed([Self.reply])
        try model.perform(action: "Reply", id: 0)
        try model.submitField(id: 0, text: "hello")
        let event = try #require(recorder.events.last)
        #expect(event.kind == .submitField)
        #expect(event.id == 0)
        #expect(event.text == "hello")
        #expect(event.outcome == .applied)
        #expect(event.state.notifications.isEmpty)
    }

    @Test func failedActionIsReportedAndRethrown() throws {
        let (model, recorder) = Self.observed([Self.reply])
        #expect(throws: DemoNotificationsError.self) {
            try model.perform(action: "Nope", id: 0)
        }
        #expect(throws: DemoNotificationsError.notPresented(id: 9)) {
            try model.press(id: 9)
        }
        let events = recorder.events
        #expect(events.map(\.outcome) == [.failed, .failed])
        #expect(events[0].action == "Nope")
        #expect(events[0].id == 0)
        #expect(events[0].error?.isEmpty == false)
        #expect(events[1].id == 9)
        #expect(events[1].state.notifications.map(\.title) == ["A"])
    }

    @Test func sequenceNumbersIncreaseAcrossEveryKind() throws {
        let clock = Clock()
        let (model, recorder) = Self.observed(
            [Self.reply, DemoNotification(title: "T", leavesAfter: 1)], clock: clock)
        model.ready()
        model.setListOpen(true)
        try model.perform(action: "Reply", id: 0)
        clock.advance(2)
        model.advance()
        try model.submitField(id: 0, text: "x")
        model.setListOpen(false)
        #expect(recorder.events.map(\.seq) == [1, 2, 3, 4, 5, 6])
        #expect(
            recorder.events.map(\.event) == [
                .ready, .listOpened, .action, .departed, .action, .listClosed,
            ])
    }

    @Test func clearAllForAppReportsTheTargetID() throws {
        let (model, recorder) = Self.observed([
            DemoNotification(app: "Mail", title: "A"), DemoNotification(app: "Cal", title: "B"),
        ])
        try model.clearAll(forApp: 1)
        let event = try #require(recorder.events.first)
        #expect(event.kind == .clearAll)
        #expect(event.id == 1)
        #expect(event.outcome == .applied)
        #expect(event.state.notifications.map(\.title) == ["A"])
    }

    @Test func clearAllByIDReportsTheTargetID() throws {
        let (model, recorder) = Self.observed([
            DemoNotification(title: "Inbox", members: [DemoNotification(title: "One")])
        ])
        try model.clearAll(id: 0)
        let event = try #require(recorder.events.first)
        #expect(event.kind == .clearAll)
        #expect(event.id == 0)
        #expect(event.state.notifications.isEmpty)
    }

    @Test func renderSnapshotCarriesTheLastSequenceNumber() throws {
        let (model, recorder) = Self.observed([DemoNotification(title: "A")])
        #expect(model.renderSnapshot().seq == 0)
        try model.press(id: 0)
        let snapshot = model.renderSnapshot()
        #expect(snapshot.seq == recorder.events.last?.seq)
        #expect(snapshot.presented.isEmpty)
        #expect(snapshot.listOpen == false)
    }

    @Test func advancingFromAnotherThreadDuringASlowCloseNeitherSwallowsNorInventsEvents()
        async throws
    {
        let clock = Clock()
        let (model, recorder) = Self.observed(
            [
                DemoNotification(title: "Slow", takes: 0.4),
                DemoNotification(title: "Leaving", leavesAfter: 1),
            ], clock: clock)
        let closing = Task.detached { try model.dismiss(id: 0) }
        try await Task.sleep(nanoseconds: 100_000_000)
        clock.advance(2)
        model.advance()
        try await closing.value
        #expect(recorder.events.map(\.event) == [.departed, .action])
        #expect(recorder.events.map(\.id) == [1, 0])
        #expect(recorder.events[0].state.notifications.map(\.title) == ["Slow"])
        #expect(recorder.events[1].outcome == .applied)
        #expect(recorder.events[1].state.notifications.isEmpty)
        #expect(recorder.events.map(\.seq) == [1, 2])
    }

    @Test func encodesAsStableFlatJSON() throws {
        let (model, recorder) = Self.observed([Self.reply])
        try model.perform(action: "Reply", id: 0)
        try model.submitField(id: 0, text: "hi")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let line = String(
            decoding: try encoder.encode(try #require(recorder.events.last)), as: UTF8.self)
        #expect(
            line
                == #"{"event":"action","id":0,"kind":"submit-field","outcome":"applied","seq":2,"state":{"listOpen":false,"notifications":[]},"text":"hi"}"#
        )
        let decoded = try JSONDecoder().decode(DemoEvent.self, from: Data(line.utf8))
        #expect(decoded == recorder.events.last)
    }
}
