import CoreGraphics
import Foundation

public struct ActionPanelSpec: Equatable, Sendable {
    public var entries: [String]
    public var frame: CGRect

    public init(entries: [String], frame: CGRect) {
        self.entries = entries
        self.frame = frame
    }
}

public enum ActionPanelLayout {
    public static let gap: CGFloat = 8
    public static let width: CGFloat = 160
    public static let builtInEntries = ["Activate", "Dismiss"]

    public static func panels(
        for notifications: [PresentedNotification],
        width: CGFloat = ActionPanelLayout.width,
        gap: CGFloat = ActionPanelLayout.gap
    ) -> [ActionPanelSpec] {
        notifications.map { n in
            ActionPanelSpec(
                entries: builtInEntries + n.item.actions,
                frame: CGRect(
                    x: n.frame.minX - gap - width,
                    y: n.frame.minY,
                    width: width,
                    height: n.frame.height))
        }
    }
}
