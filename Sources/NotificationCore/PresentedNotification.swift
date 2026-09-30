import CoreGraphics
import Foundation

public struct PresentedNotification: Equatable, Sendable {
    public var item: NotificationItem
    public var frame: CGRect

    public init(item: NotificationItem, frame: CGRect) {
        self.item = item
        self.frame = frame
    }
}

extension PresentedNotification {
    public static func topDown(_ presented: [PresentedNotification]) -> [PresentedNotification] {
        presented.enumerated()
            .sorted { ($0.element.frame.minY, $0.offset) < ($1.element.frame.minY, $1.offset) }
            .map(\.element)
    }
}
