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

    private let anchor = CGRect(x: 1000, y: 50, width: 360, height: 80)

    @Test func entriesAreActivateDismissThenActionsInOrder() {
        let n = presented(0, actions: ["Reply", "Snooze"], frame: anchor)
        let spec = ActionPanelLayout.panel(for: [n], selectedIndex: 0)
        #expect(spec?.entries == ["Activate", "Dismiss", "Reply", "Snooze"])
    }

    @Test func entriesWithZeroActionsAreActivateAndDismiss() {
        let n = presented(0, frame: anchor)
        #expect(
            ActionPanelLayout.panel(for: [n], selectedIndex: 0)?.entries
                == ["Activate", "Dismiss"])
    }

    @Test func collapsedStackEntriesAreExpandDismissThenActionsWithoutClearAll() {
        let item = NotificationItem(
            index: 0, actions: ["Clear All", "Reply"], isCollapsedStack: true)
        #expect(ActionPanelLayout.entries(for: item) == ["Expand", "Dismiss", "Reply"])
    }

    @Test func plainItemEntriesAreActivateDismissThenActions() {
        let item = NotificationItem(index: 0, actions: ["Reply"])
        #expect(ActionPanelLayout.entries(for: item) == ["Activate", "Dismiss", "Reply"])
    }

    @Test func expandIsActivatedBySpace() {
        let item = NotificationItem(index: 0, actions: ["Clear All"], isCollapsedStack: true)
        let n = PresentedNotification(item: item, frame: anchor)
        let spec = ActionPanelLayout.panel(for: [n], selectedIndex: 0)
        #expect(spec?.entries == ["Expand", "Dismiss"])
        #expect(spec?.activators == ["Space", "d"])
    }

    @Test func onlyTheSelectedNotificationGetsAPanel() {
        let a = presented(0, actions: ["Reply"], frame: anchor)
        let b = presented(1, actions: ["Snooze"], frame: anchor.offsetBy(dx: 0, dy: 100))
        let spec = ActionPanelLayout.panel(for: [a, b], selectedIndex: 1)
        #expect(spec?.entries == ["Activate", "Dismiss", "Snooze"])
        #expect(spec?.activators == ["Space", "d", "s"])
        #expect(spec?.anchor == anchor.offsetBy(dx: 0, dy: 100))
    }

    @Test func nilSelectionYieldsNoPanel() {
        let n = presented(0, frame: anchor)
        #expect(ActionPanelLayout.panel(for: [n], selectedIndex: nil) == nil)
    }

    @Test func selectionOutsideTheListYieldsNoPanel() {
        let n = presented(0, frame: anchor)
        #expect(ActionPanelLayout.panel(for: [n], selectedIndex: 1) == nil)
    }

    @Test func emptyInputYieldsNoPanel() {
        #expect(ActionPanelLayout.panel(for: [], selectedIndex: 0) == nil)
    }

    @Test func activatorLabelsAreLowerCase() {
        let n = presented(0, actions: ["Reply"], frame: anchor)
        let spec = ActionPanelLayout.panel(for: [n], selectedIndex: 0)
        #expect(spec?.activatorLabels == ["space", "d", "r"])
    }

    @Test func frameSitsLeftOfAndTopAlignedWithTheNotification() {
        let frame = ActionPanelLayout.frame(
            anchor: anchor, contentSize: CGSize(width: 120, height: 40), gap: 10)
        #expect(frame == CGRect(x: 870, y: 50, width: 120, height: 80))
    }

    @Test func frameIsAtLeastAsTallAsTheNotificationAndMayBeTaller() {
        let short = ActionPanelLayout.frame(
            anchor: anchor, contentSize: CGSize(width: 120, height: 40))
        let tall = ActionPanelLayout.frame(
            anchor: anchor, contentSize: CGSize(width: 120, height: 130))
        #expect(short.height == 80)
        #expect(tall.height == 130)
        #expect(tall.minY == anchor.minY)
    }

    @Test func frameWidthIsTheContentWidthAndTheDefaultGapIsEight() {
        let frame = ActionPanelLayout.frame(
            anchor: anchor, contentSize: CGSize(width: 150, height: 40))
        #expect(frame == CGRect(x: 842, y: 50, width: 150, height: 80))
    }
}
