import CoreGraphics
import Testing

@testable import NotificationCore

@Suite struct PresentedNotificationTopDownTests {
    private func presented(_ title: String, y: CGFloat) -> PresentedNotification {
        PresentedNotification(
            item: NotificationItem(index: 0, app: "App", title: title),
            frame: CGRect(x: 0, y: y, width: 300, height: 60))
    }

    /// RIM-11: index 0 is the topmost presented notification whatever the AX order.
    @Test func sortsByFrameTopFirst() {
        let sorted = PresentedNotification.topDown([
            presented("low", y: 200), presented("top", y: 10), presented("mid", y: 100),
        ])
        #expect(sorted.map(\.item.title) == ["top", "mid", "low"])
    }

    @Test func keepsTheReadOrderOnTies() {
        let sorted = PresentedNotification.topDown([
            presented("first", y: 100), presented("second", y: 100),
        ])
        #expect(sorted.map(\.item.title) == ["first", "second"])
    }
}
