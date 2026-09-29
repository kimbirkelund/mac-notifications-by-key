import CoreGraphics
import Foundation
import Testing

@testable import NotificationCore

@Suite struct ActionPanelLayoutTests {
    private func presented(
        _ index: Int, actions: [String] = [], frame: CGRect
    ) -> PresentedNotification {
        PresentedNotification(
            item: NotificationItem(index: index, actions: actions), frame: frame)
    }

    @Test func entriesAreActivateDismissThenActionsInOrder() {
        let n = presented(
            0, actions: ["Reply", "Snooze"], frame: CGRect(x: 1000, y: 50, width: 360, height: 80))
        let specs = ActionPanelLayout.panels(for: [n])
        #expect(specs.count == 1)
        #expect(specs[0].entries == ["Activate", "Dismiss", "Reply", "Snooze"])
    }

    @Test func entriesWithZeroActionsAreActivateAndDismiss() {
        let n = presented(0, frame: CGRect(x: 1000, y: 50, width: 360, height: 80))
        #expect(ActionPanelLayout.panels(for: [n])[0].entries == ["Activate", "Dismiss"])
    }

    @Test func panelIsLeftOfAndTopAlignedWithNotification() {
        let n = presented(0, frame: CGRect(x: 1000, y: 50, width: 360, height: 80))
        let frame = ActionPanelLayout.panels(for: [n], width: 200, gap: 10)[0].frame
        #expect(frame == CGRect(x: 790, y: 50, width: 200, height: 80))
    }

    @Test func defaultsAreEightPointGapAndOneSixtyWidth() {
        let n = presented(0, frame: CGRect(x: 1000, y: 50, width: 360, height: 80))
        let frame = ActionPanelLayout.panels(for: [n])[0].frame
        #expect(frame == CGRect(x: 832, y: 50, width: 160, height: 80))
    }

    @Test func oneSpecPerNotificationInOrder() {
        let a = presented(0, actions: ["A"], frame: CGRect(x: 1000, y: 50, width: 360, height: 80))
        let b = presented(1, frame: CGRect(x: 1000, y: 150, width: 360, height: 100))
        let specs = ActionPanelLayout.panels(for: [a, b])
        #expect(specs.map(\.entries.count) == [3, 2])
        #expect(specs[1].frame.minY == 150)
        #expect(specs[1].frame.height == 100)
    }

    @Test func emptyInputYieldsNoPanels() {
        #expect(ActionPanelLayout.panels(for: []).isEmpty)
    }
}
