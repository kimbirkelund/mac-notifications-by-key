import CoreGraphics
import DemoNotifications
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

    @Test func reportsATrustedOpenPanelWithoutANotificationCenter() throws {
        let access = Self.access([])
        #expect(access.isTrusted)
        #expect(access.isPanelOpen)
        #expect(access.notificationCenterPID() == nil)
        try access.setPanelOpen(false)
        #expect(access.isPanelOpen)
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

    @Test func modelErrorsSurfaceAsNbkErrors() {
        let access = Self.access([DemoNotification(title: "A")])
        #expect {
            try access.dismiss(index: 1)
        } throws: { error in
            guard case .indexOutOfRange(let requested, let count) = error as? NbkError else {
                return false
            }
            return requested == 1 && count == 1
        }
        #expect {
            try access.perform(action: "Reply", index: 0)
        } throws: { error in
            guard case .unknownAction(let name, _) = error as? NbkError else { return false }
            return name == "Reply"
        }
    }
}
