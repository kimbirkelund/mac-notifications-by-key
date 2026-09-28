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
