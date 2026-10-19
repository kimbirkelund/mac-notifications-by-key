import CoreGraphics
import Foundation
import NotificationAX
import NotificationCore
import Testing

@testable import InteractiveMode

@Suite struct DemoAccessTests {
    private static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private static func access(_ notifications: [DemoNotification]) -> DemoNotificationCenterAccess
    {
        DemoNotificationCenterAccess(notifications: notifications, screenFrame: screen)
    }

    private static func titles(_ access: DemoNotificationCenterAccess) throws -> [String?] {
        try access.readPresented().map(\.item.title)
    }

    /// RIM-21: the file's notifications are presented newest first, stacked from the top-right.
    @Test func framesStackFromTheTopRightNewestFirst() throws {
        let access = Self.access([
            DemoNotification(title: "A"), DemoNotification(title: "B"),
            DemoNotification(title: "C"),
        ])
        let presented = try access.readPresented()
        #expect(presented.map(\.item.title) == ["A", "B", "C"])
        #expect(presented.map(\.item.index) == [0, 1, 2])
        #expect(
            presented.map(\.frame) == [
                CGRect(x: 1136, y: 60, width: 360, height: 80),
                CGRect(x: 1136, y: 150, width: 360, height: 80),
                CGRect(x: 1136, y: 240, width: 360, height: 80),
            ])
    }

    @Test func framesFollowTheGivenScreenOrigin() throws {
        let access = DemoNotificationCenterAccess(
            notifications: [DemoNotification(title: "A")],
            screenFrame: CGRect(x: 1512, y: -200, width: 1920, height: 1080))
        #expect(
            try access.readPresented().map(\.frame) == [
                CGRect(x: 3056, y: -140, width: 360, height: 80)
            ])
    }

    @Test func readListsTheSameItemsAsPresented() throws {
        let access = Self.access([
            DemoNotification(app: "Mail", title: "A", actions: [DemoAction(name: "Archive")])
        ])
        #expect(
            try access.read(wait: 0) == [
                NotificationItem(
                    index: 0, app: "Mail", title: "A", subtitle: nil, body: nil,
                    actions: ["Archive"])
            ])
    }

    @Test func reportsATrustedOpenPanelWithoutANotificationCenter() throws {
        let access = Self.access([])
        #expect(access.isTrusted)
        #expect(access.isPanelOpen)
        #expect(access.notificationCenterPID() == nil)
        try access.setPanelOpen(false)
        #expect(access.isPanelOpen)
    }

    @Test func clearAllForAppThrowsIndexOutOfRangeAndRemovesNothing() throws {
        let access = Self.access([DemoNotification(app: "Mail", title: "A")])
        #expect(throws: NbkError.self) { try access.clearAll(forApp: 1) }
        #expect(try Self.titles(access) == ["A"])
    }

    @Test func clearAllForAppRemovesOnlyItemsOfThatApp() throws {
        let access = Self.access([
            DemoNotification(app: "Mail", title: "A"), DemoNotification(title: "B"),
            DemoNotification(app: "Mail", title: "C"), DemoNotification(title: "D"),
            DemoNotification(app: "Chat", title: "E"),
        ])
        try access.clearAll(forApp: 1)
        #expect(try Self.titles(access) == ["A", "C", "E"])
        try access.clearAll(forApp: 0)
        #expect(try Self.titles(access) == ["E"])
    }

    @Test func dismissRemovesTheNotificationAndRenumbers() throws {
        let access = Self.access([
            DemoNotification(title: "A"), DemoNotification(title: "B"),
            DemoNotification(title: "C"),
        ])
        try access.dismiss(index: 1)
        let presented = try access.readPresented()
        #expect(presented.map(\.item.title) == ["A", "C"])
        #expect(presented.map(\.item.index) == [0, 1])
        #expect(presented.map(\.frame.minY) == [60, 150])
    }

    @Test func pressRemovesWhenActivateCloses() throws {
        let access = Self.access([DemoNotification(title: "A"), DemoNotification(title: "B")])
        try access.press(index: 0)
        #expect(try Self.titles(access) == ["B"])
    }

    @Test func pressKeepsWhenActivateDoesNotClose() throws {
        let access = Self.access([DemoNotification(title: "A", activateCloses: false)])
        try access.press(index: 0)
        #expect(try Self.titles(access) == ["A"])
    }

    @Test func performRemovesWhenTheActionCloses() throws {
        let access = Self.access([
            DemoNotification(title: "A", actions: [DemoAction(name: "Archive")])
        ])
        try access.perform(action: "Archive", index: 0)
        #expect(try Self.titles(access) == [])
    }

    @Test func performKeepsWhenTheActionDoesNotClose() throws {
        let access = Self.access([
            DemoNotification(title: "A", actions: [DemoAction(name: "Reply", closes: false)])
        ])
        try access.perform(action: "Reply", index: 0)
        #expect(try Self.titles(access) == ["A"])
    }

    @Test func performThrowsUnknownActionForAnUnlistedName() throws {
        let access = Self.access([
            DemoNotification(title: "A", actions: [DemoAction(name: "Archive")])
        ])
        #expect {
            try access.perform(action: "Reply", index: 0)
        } throws: { error in
            guard case .unknownAction(let name, let available) = error as? NbkError else {
                return false
            }
            return name == "Reply" && available == ["Archive"]
        }
        #expect(try Self.titles(access) == ["A"])
    }

    @Test func outOfRangeIndexThrows() {
        let access = Self.access([DemoNotification(title: "A")])
        #expect {
            try access.dismiss(index: 1)
        } throws: { error in
            guard case .indexOutOfRange(let requested, let count) = error as? NbkError else {
                return false
            }
            return requested == 1 && count == 1
        }
    }

    @MainActor @Test func demoModeTurnsAnAppKitScreenFrameIntoTopLeftFrames() throws {
        let mode = try DemoMode(
            file: DemoFile(notifications: [DemoNotification(title: "A")]),
            mainScreenFrame: { CGRect(x: 0, y: 0, width: 1512, height: 982) },
            primaryScreenHeight: 982)
        #expect(
            try mode.access.readPresented().map(\.frame) == [
                CGRect(x: 1136, y: 60, width: 360, height: 80)
            ])
    }

    @MainActor @Test func demoModeFlipsAnOffsetMainScreenIntoTopLeftFrames() throws {
        let mode = try DemoMode(
            file: DemoFile(notifications: [
                DemoNotification(title: "A"), DemoNotification(title: "B"),
            ]),
            mainScreenFrame: { CGRect(x: 0, y: 982, width: 1920, height: 1080) },
            primaryScreenHeight: 982)
        #expect(
            try mode.access.readPresented().map(\.frame) == [
                CGRect(x: 1544, y: -1020, width: 360, height: 80),
                CGRect(x: 1544, y: -930, width: 360, height: 80),
            ])
    }

    @MainActor @Test func demoModeThrowsNoScreenWithoutAMainScreen() {
        #expect(throws: InteractiveError.noScreen) {
            try DemoMode(
                file: DemoFile(notifications: []), mainScreenFrame: { nil },
                primaryScreenHeight: 982)
        }
    }

    private static func stack() -> DemoNotificationCenterAccess {
        access([
            DemoNotification(
                title: "S",
                members: [
                    DemoNotification(title: "m1"), DemoNotification(title: "m2"),
                ]),
            DemoNotification(title: "P"),
        ])
    }

    @Test func expandSplicesMembersInPlaceAndTheyAreNotStacks() throws {
        let access = Self.stack()
        try access.expand(index: 0)
        let presented = try access.readPresented()
        #expect(presented.map(\.item.title) == ["m1", "m2", "P"])
        #expect(presented.map(\.item.index) == [0, 1, 2])
        #expect(presented.map(\.item.isCollapsedStack) == [false, false, false])
    }

    @Test func dismissRemovesTheWholeStack() throws {
        let access = Self.stack()
        try access.dismiss(index: 0)
        #expect(try Self.titles(access) == ["P"])
    }

    @Test func expandOnAPlainItemThrowsUnknownAction() {
        do {
            try Self.stack().expand(index: 1)
            Issue.record("expected throw")
        } catch NbkError.unknownAction(let name, _) {
            #expect(name == "Expand")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func pressOnAStackThrowsUnknownAction() {
        do {
            try Self.stack().press(index: 0)
            Issue.record("expected throw")
        } catch NbkError.unknownAction(let name, _) {
            #expect(name == "Activate")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}
