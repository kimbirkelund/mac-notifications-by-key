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

    @Test(arguments: [
        (0, 3, false, true), (1, 3, true, true), (2, 3, true, false), (0, 1, false, false),
    ])
    func movementHintsFollowSelectedIndexAndCount(
        index: Int, count: Int, up: Bool, down: Bool
    ) {
        let list = (0..<count).map { presented($0, frame: anchor) }
        let spec = ActionPanelLayout.panel(for: list, selectedIndex: index)
        #expect(spec?.canMoveUp == up)
        #expect(spec?.canMoveDown == down)
    }

    @Test func dismissRowLabelShowsAllThreeVariantsForPlainItem() {
        let n = presented(0, actions: ["Reply"], frame: anchor)
        let spec = ActionPanelLayout.panel(for: [n], selectedIndex: 0)
        #expect(spec?.rowLabels.count == 3)
        #expect(spec?.rowLabels[1].activator == "d / D / X")
        #expect(spec?.rowLabels[1].entry == "Dismiss this / app / all")
        #expect(spec?.rowLabels[0].activator == "space")
        #expect(spec?.rowLabels[0].entry == "Activate")
        #expect(spec?.rowLabels[2].entry == "Reply")
        #expect(spec?.rowLabels[2].activator == spec?.activatorLabels[2])
    }

    @Test func dismissRowLabelShowsAllThreeVariantsForStack() {
        let item = NotificationItem(index: 0, actions: [], isCollapsedStack: true)
        let n = PresentedNotification(item: item, frame: anchor)
        let spec = ActionPanelLayout.panel(for: [n], selectedIndex: 0)
        #expect(spec?.rowLabels[0].activator == "space")
        #expect(spec?.rowLabels[0].entry == "Expand")
        #expect(spec?.rowLabels[1].activator == "d / D / X")
        #expect(spec?.rowLabels[1].entry == "Dismiss this / app / all")
    }

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

    @Test func plainItemEntriesOmitClose() {
        let item = NotificationItem(index: 0, actions: ["Close", "Reply"])
        #expect(ActionPanelLayout.entries(for: item) == ["Activate", "Dismiss", "Reply"])
    }

    @Test func collapsedStackEntriesOmitCloseAndClearAll() {
        let item = NotificationItem(
            index: 0, actions: ["Close", "Clear All", "Reply"], isCollapsedStack: true)
        #expect(ActionPanelLayout.entries(for: item) == ["Expand", "Dismiss", "Reply"])
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

    @Test func panelCoversWhatThePresentedNotificationReachesBelowItsFrame() {
        let item = NotificationItem(index: 0, actions: ["Clear All"], isCollapsedStack: true)
        let n = PresentedNotification(item: item, frame: anchor, extentBelow: 16)
        let spec = ActionPanelLayout.panel(for: [n], selectedIndex: 0)
        #expect(spec?.coveredExtent == 16)
        #expect(spec?.coveredHeight == anchor.height + 16)
    }

    @Test func plainNotificationCoversOnlyItsOwnFrame() {
        let spec = ActionPanelLayout.panel(for: [presented(0, frame: anchor)], selectedIndex: 0)
        #expect(spec?.coveredExtent == 0)
        #expect(spec?.coveredHeight == anchor.height)
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
