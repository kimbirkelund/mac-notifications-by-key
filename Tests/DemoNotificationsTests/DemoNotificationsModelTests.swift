import Foundation
import NotificationCore
import Testing

@testable import DemoNotifications

@Suite struct DemoNotificationsModelTests {
    private static func model(_ notifications: [DemoNotification]) -> DemoNotificationsModel {
        DemoNotificationsModel(notifications: notifications)
    }

    private static func titles(_ model: DemoNotificationsModel) -> [String?] {
        model.items().map(\.title)
    }

    @Test func itemsCarryTheNotificationFields() {
        let model = Self.model([
            DemoNotification(app: "Mail", title: "A", actions: [DemoAction(name: "Archive")])
        ])
        #expect(
            model.items() == [
                NotificationItem(
                    index: 0, app: "Mail", title: "A", subtitle: nil, body: nil,
                    actions: ["Archive"])
            ])
    }

    @Test func presentedCountsAStacksHiddenMembers() throws {
        let model = Self.model([
            DemoNotification(
                app: "Mail", title: "Inbox",
                members: [DemoNotification(title: "One"), DemoNotification(title: "Two")]),
            DemoNotification(title: "B"),
        ])
        #expect(model.presented().map(\.hiddenMembers) == [2, 0])
        #expect(model.presented().map(\.item) == model.items())
        try model.expand(index: 0)
        #expect(model.presented().map(\.hiddenMembers) == [0, 0, 0])
    }

    @Test func dismissByIDTargetsTheSameEntryAfterAnEarlierOneLeaves() throws {
        let model = Self.model([
            DemoNotification(title: "A"), DemoNotification(title: "B"),
            DemoNotification(title: "C"),
        ])
        let c = try #require(model.presented().first { $0.item.title == "C" })
        try model.dismiss(index: 0)
        try model.dismiss(id: c.id)
        #expect(Self.titles(model) == ["B"])
    }

    @Test func expandedMembersGetIDsOfTheirOwn() throws {
        let model = Self.model([
            DemoNotification(
                title: "Inbox",
                members: [
                    DemoNotification(title: "One", actions: [DemoAction(name: "Archive")]),
                    DemoNotification(title: "Two"),
                ]),
            DemoNotification(title: "B"),
        ])
        let stack = try #require(model.presented().first)
        try model.expand(id: stack.id)
        let ids = model.presented().map(\.id)
        #expect(Set(ids).count == 3)
        #expect(!ids.contains(stack.id))
        try model.perform(action: "Archive", id: ids[0])
        #expect(Self.titles(model) == ["Two", "B"])
    }

    @Test func actingOnAnIDNoLongerPresentedThrowsAndRemovesNothing() throws {
        let model = Self.model([DemoNotification(title: "A"), DemoNotification(title: "B")])
        let a = try #require(model.presented().first)
        try model.dismiss(id: a.id)
        #expect(throws: DemoNotificationsError.notPresented(id: a.id)) {
            try model.press(id: a.id)
        }
        #expect(Self.titles(model) == ["B"])
    }

    @Test func clearAllForAppThrowsIndexOutOfRangeAndRemovesNothing() throws {
        let model = Self.model([DemoNotification(app: "Mail", title: "A")])
        #expect(throws: DemoNotificationsError.self) { try model.clearAll(forApp: 1) }
        #expect(Self.titles(model) == ["A"])
    }

    @Test func clearAllForAppRemovesOnlyItemsOfThatApp() throws {
        let model = Self.model([
            DemoNotification(app: "Mail", title: "A"), DemoNotification(title: "B"),
            DemoNotification(app: "Mail", title: "C"), DemoNotification(title: "D"),
            DemoNotification(app: "Chat", title: "E"),
        ])
        try model.clearAll(forApp: 1)
        #expect(Self.titles(model) == ["A", "C", "E"])
        try model.clearAll(forApp: 0)
        #expect(Self.titles(model) == ["E"])
    }

    @Test func dismissRemovesTheNotificationAndRenumbers() throws {
        let model = Self.model([
            DemoNotification(title: "A"), DemoNotification(title: "B"),
            DemoNotification(title: "C"),
        ])
        try model.dismiss(index: 1)
        let presented = model.items()
        #expect(presented.map(\.title) == ["A", "C"])
        #expect(presented.map(\.index) == [0, 1])
    }

    @Test func pressRemovesWhenActivateCloses() throws {
        let model = Self.model([DemoNotification(title: "A"), DemoNotification(title: "B")])
        try model.press(index: 0)
        #expect(Self.titles(model) == ["B"])
    }

    @Test func pressKeepsWhenActivateDoesNotClose() throws {
        let model = Self.model([DemoNotification(title: "A", activateCloses: false)])
        try model.press(index: 0)
        #expect(Self.titles(model) == ["A"])
    }

    @Test func performRemovesWhenTheActionCloses() throws {
        let model = Self.model([
            DemoNotification(title: "A", actions: [DemoAction(name: "Archive")])
        ])
        try model.perform(action: "Archive", index: 0)
        #expect(Self.titles(model) == [])
    }

    @Test func performKeepsWhenTheActionDoesNotClose() throws {
        let model = Self.model([
            DemoNotification(title: "A", actions: [DemoAction(name: "Reply", closes: false)])
        ])
        try model.perform(action: "Reply", index: 0)
        #expect(Self.titles(model) == ["A"])
    }

    @Test func performThrowsUnknownActionForAnUnlistedName() throws {
        let model = Self.model([
            DemoNotification(title: "A", actions: [DemoAction(name: "Archive")])
        ])
        #expect {
            try model.perform(action: "Reply", index: 0)
        } throws: { error in
            guard case .unknownAction(let name, let available) = error as? DemoNotificationsError
            else {
                return false
            }
            return name == "Reply" && available == ["Archive"]
        }
        #expect(Self.titles(model) == ["A"])
    }

    @Test func dismissOnANotificationThatTakesTimeReturnsOnlyAfterItsDelay() throws {
        let model = Self.model([
            DemoNotification(title: "A", takes: 0.3), DemoNotification(title: "B"),
        ])
        let started = Date()
        try model.dismiss(index: 0)
        #expect(Date().timeIntervalSince(started) >= 0.3)
        #expect(Self.titles(model) == ["B"])
    }

    @Test func thePresentedListIsReadableWhileAnEntryTakesTime() async throws {
        let model = Self.model([DemoNotification(title: "A", takes: 0.5)])
        nonisolated(unsafe) let slow = model
        let dismissal = Task.detached { try slow.dismiss(index: 0) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(Self.titles(model) == ["A"])
        try await dismissal.value
        #expect(Self.titles(model) == [])
    }

    @Test func outOfRangeIndexThrows() {
        let model = Self.model([DemoNotification(title: "A")])
        #expect {
            try model.dismiss(index: 1)
        } throws: { error in
            guard case .indexOutOfRange(let requested, let count) = error as? DemoNotificationsError
            else {
                return false
            }
            return requested == 1 && count == 1
        }
    }

    private static func stack() -> DemoNotificationsModel {
        model([
            DemoNotification(
                title: "S",
                members: [
                    DemoNotification(title: "m1"), DemoNotification(title: "m2"),
                ]),
            DemoNotification(title: "P"),
        ])
    }

    @Test func expandSplicesMembersInPlaceAndTheyAreNotStacks() throws {
        let model = Self.stack()
        try model.expand(index: 0)
        let presented = model.items()
        #expect(presented.map(\.title) == ["m1", "m2", "P"])
        #expect(presented.map(\.index) == [0, 1, 2])
        #expect(presented.map(\.isCollapsedStack) == [false, false, false])
    }

    @Test func dismissRemovesTheWholeStack() throws {
        let model = Self.stack()
        try model.dismiss(index: 0)
        #expect(Self.titles(model) == ["P"])
    }

    @Test func expandOnAPlainItemThrowsUnknownAction() {
        do {
            try Self.stack().expand(index: 1)
            Issue.record("expected throw")
        } catch DemoNotificationsError.unknownAction(let name, _) {
            #expect(name == "Expand")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func pressOnAStackThrowsUnknownAction() {
        do {
            try Self.stack().press(index: 0)
            Issue.record("expected throw")
        } catch DemoNotificationsError.unknownAction(let name, _) {
            #expect(name == "Activate")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    private final class Clock: @unchecked Sendable {
        var date = Date(timeIntervalSince1970: 1_000)
        func advance(_ seconds: TimeInterval) { date += seconds }
    }

    private static func timed(
        _ notifications: [DemoNotification], clock: Clock
    ) -> DemoNotificationsModel {
        DemoNotificationsModel(notifications: notifications, now: { clock.date })
    }

    @Test func notificationIsNotPresentedBeforeArrivesAfterAndIsAfter() throws {
        let clock = Clock()
        let model = Self.timed(
            [DemoNotification(title: "A"), DemoNotification(title: "B", arrivesAfter: 2)],
            clock: clock)
        #expect(Self.titles(model) == ["A"])
        clock.advance(1.9)
        #expect(Self.titles(model) == ["A"])
        clock.advance(0.1)
        #expect(Self.titles(model) == ["A", "B"])
    }

    @Test func notificationIsGoneAtLeavesAfter() throws {
        let clock = Clock()
        let model = Self.timed(
            [DemoNotification(title: "A", leavesAfter: 3), DemoNotification(title: "B")],
            clock: clock)
        #expect(Self.titles(model) == ["A", "B"])
        clock.advance(3)
        #expect(Self.titles(model) == ["B"])
    }

    @Test func dismissAfterAnArrivalRemovesTheItemThePresentedIndexNames() throws {
        let clock = Clock()
        let model = Self.timed(
            [
                DemoNotification(title: "late-top", arrivesAfter: 1),
                DemoNotification(title: "A"), DemoNotification(title: "B"),
            ], clock: clock)
        #expect(Self.titles(model) == ["A", "B"])
        clock.advance(1)
        #expect(Self.titles(model) == ["late-top", "A", "B"])
        try model.dismiss(index: 1)
        #expect(Self.titles(model) == ["late-top", "B"])
    }

    @Test func dismissIndexSkipsNotYetArrivedNotifications() throws {
        let clock = Clock()
        let model = Self.timed(
            [
                DemoNotification(title: "A"), DemoNotification(title: "later", arrivesAfter: 5),
                DemoNotification(title: "B"),
            ], clock: clock)
        try model.dismiss(index: 1)
        clock.advance(5)
        #expect(Self.titles(model) == ["A", "later"])
    }

    @Test func expandedMembersLeaveWhenTheStackWould() throws {
        let clock = Clock()
        let model = Self.timed(
            [
                DemoNotification(
                    title: "S",
                    members: [DemoNotification(title: "m1"), DemoNotification(title: "m2")],
                    leavesAfter: 4),
                DemoNotification(title: "B"),
            ], clock: clock)
        try model.expand(index: 0)
        #expect(Self.titles(model) == ["m1", "m2", "B"])
        clock.advance(4)
        #expect(Self.titles(model) == ["B"])
    }

    @Test func clearAllForAppLeavesANotYetArrivedNotificationOfThatApp() throws {
        let clock = Clock()
        let model = Self.timed(
            [
                DemoNotification(app: "Mail", title: "A"),
                DemoNotification(app: "Mail", title: "later", arrivesAfter: 5),
                DemoNotification(app: "Chat", title: "B"),
            ], clock: clock)
        try model.clearAll(forApp: 0)
        #expect(Self.titles(model) == ["B"])
        clock.advance(5)
        #expect(Self.titles(model) == ["later", "B"])
    }

    @Test func clearAllLeavesANotYetArrivedNotification() throws {
        let clock = Clock()
        let model = Self.timed(
            [DemoNotification(title: "A"), DemoNotification(title: "later", arrivesAfter: 5)],
            clock: clock)
        model.clearAll()
        #expect(Self.titles(model).isEmpty)
        clock.advance(5)
        #expect(Self.titles(model) == ["later"])
    }

    @Test func expandAfterAnArrivalExpandsTheStackThePresentedIndexNames() throws {
        let clock = Clock()
        let model = Self.timed(
            [
                DemoNotification(title: "late", arrivesAfter: 1),
                DemoNotification(title: "S", members: [DemoNotification(title: "m")]),
            ], clock: clock)
        clock.advance(1)
        #expect(Self.titles(model) == ["late", "S"])
        try model.expand(index: 1)
        #expect(Self.titles(model) == ["late", "m"])
    }

}
