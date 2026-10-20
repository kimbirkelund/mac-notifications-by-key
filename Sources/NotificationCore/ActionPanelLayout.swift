import CoreGraphics
import Foundation

public struct ActionPanelSpec: Equatable, Sendable {
    public var entries: [String]
    public var activators: [String]
    public var anchor: CGRect
    public var coveredExtent: CGFloat
    public var canMoveUp: Bool
    public var canMoveDown: Bool

    public init(
        entries: [String], activators: [String], anchor: CGRect, coveredExtent: CGFloat = 0,
        canMoveUp: Bool = false, canMoveDown: Bool = false
    ) {
        self.entries = entries
        self.activators = activators
        self.anchor = anchor
        self.coveredExtent = coveredExtent
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
    }

    public var coveredHeight: CGFloat { anchor.height + coveredExtent }

    public var activatorLabels: [String] { activators.map(ActionPanelLayout.activatorLabel) }

    public var rowLabels: [(activator: String, entry: String)] {
        Array(zip(activatorLabels, entries)).enumerated().map { index, row in
            index == 1 ? ("d / D / X", "Dismiss this / app / all") : row
        }
    }
}

public enum ActionPanelLayout {
    public static let gap: CGFloat = 8

    public static func entries(for item: NotificationItem) -> [String] {
        let actions = item.actions.filter { $0 != "Close" }
        if item.isCollapsedStack {
            return ["Expand", "Dismiss"] + actions.filter { $0 != "Clear All" }
        }
        return ["Activate", "Dismiss"] + actions
    }

    public static func activatorLabel(_ activator: String) -> String { activator.lowercased() }

    public static func panel(
        for notifications: [PresentedNotification], selectedIndex: Int?
    ) -> ActionPanelSpec? {
        guard let selectedIndex, notifications.indices.contains(selectedIndex) else { return nil }
        let selected = notifications[selectedIndex]
        let entries = entries(for: selected.item)
        return ActionPanelSpec(
            entries: entries, activators: ActivatorAssignment.keys(for: entries),
            anchor: selected.frame, coveredExtent: selected.extentBelow,
            canMoveUp: selectedIndex > 0, canMoveDown: selectedIndex < notifications.count - 1)
    }

    public static func frame(
        anchor: CGRect, contentSize: CGSize, gap: CGFloat = ActionPanelLayout.gap
    ) -> CGRect {
        CGRect(
            x: anchor.minX - gap - contentSize.width,
            y: anchor.minY,
            width: contentSize.width,
            height: max(contentSize.height, anchor.height))
    }
}
