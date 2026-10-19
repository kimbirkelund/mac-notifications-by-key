import CoreGraphics
import Foundation

public struct ActionPanelSpec: Equatable, Sendable {
    public var entries: [String]
    public var activators: [String]
    public var anchor: CGRect

    public init(entries: [String], activators: [String], anchor: CGRect) {
        self.entries = entries
        self.activators = activators
        self.anchor = anchor
    }

    public var activatorLabels: [String] { activators.map(ActionPanelLayout.activatorLabel) }
}

public enum ActionPanelLayout {
    public static let gap: CGFloat = 8

    public static func entries(for item: NotificationItem) -> [String] {
        if item.isCollapsedStack {
            return ["Expand", "Dismiss"] + item.actions.filter { $0 != "Clear All" }
        }
        return ["Activate", "Dismiss"] + item.actions
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
            anchor: selected.frame)
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
