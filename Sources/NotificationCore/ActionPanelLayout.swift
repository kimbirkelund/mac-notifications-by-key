import CoreGraphics
import Foundation

public struct ActionPanelSpec: Equatable, Sendable {
    public var entries: [String]
    public var frame: CGRect
    public var isSelected: Bool
    public var activators: [String]?

    public init(
        entries: [String], frame: CGRect, isSelected: Bool = false, activators: [String]? = nil
    ) {
        self.entries = entries
        self.frame = frame
        self.isSelected = isSelected
        self.activators = activators
    }
}

public enum ActionPanelLayout {
    public static let gap: CGFloat = 8
    public static let width: CGFloat = 160
    public static let builtInEntries = ["Activate", "Dismiss"]

    public static func panels(
        for notifications: [PresentedNotification],
        selectedIndex: Int? = nil,
        width: CGFloat = ActionPanelLayout.width,
        gap: CGFloat = ActionPanelLayout.gap
    ) -> [ActionPanelSpec] {
        notifications.enumerated().map { offset, n in
            let entries = builtInEntries + n.item.actions
            let isSelected = offset == selectedIndex
            return ActionPanelSpec(
                entries: entries,
                frame: CGRect(
                    x: n.frame.minX - gap - width,
                    y: n.frame.minY,
                    width: width,
                    height: n.frame.height),
                isSelected: isSelected,
                activators: isSelected ? ActivatorAssignment.keys(for: entries) : nil)
        }
    }
}
