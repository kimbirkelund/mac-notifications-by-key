import CoreGraphics
import Foundation

public struct PresentedNotification: Equatable, Sendable {
    public var item: NotificationItem
    public var frame: CGRect
    public var extentBelow: CGFloat

    public init(item: NotificationItem, frame: CGRect, extentBelow: CGFloat = 0) {
        self.item = item
        self.frame = frame
        self.extentBelow = extentBelow
    }
}

extension PresentedNotification {
    public static func topDown(_ presented: [PresentedNotification]) -> [PresentedNotification] {
        presented.enumerated()
            .sorted { ($0.element.frame.minY, $0.offset) < ($1.element.frame.minY, $1.offset) }
            .map(\.element)
    }
}
