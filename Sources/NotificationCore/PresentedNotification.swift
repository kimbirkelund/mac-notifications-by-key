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
