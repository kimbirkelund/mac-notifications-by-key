import AppKit
import DemoNotifications
import NotificationCore

final class DemoWindow: NSWindow {
    private static let cardSize = CGSize(width: 360, height: 80)
    private static let rightInset: CGFloat = 16
    private static let topInset: CGFloat = 60
    private static let rowGap: CGFloat = 6

    typealias Perform = (_ action: NotificationAction, _ id: Int, _ isStack: Bool) -> Void

    private let onAction: Perform
    private let outer = GroupView()
    private let inner = GroupView()
    private let scroll = NSScrollView()
    private let list = FlippedView()
    private let editWidgets = NSButton(title: "", target: nil, action: nil)
    private var shown: [DemoPresentedNotification]?

    init(onAction: @escaping Perform) {
        self.onAction = onAction
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        title = "Demo notifications"
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        backgroundColor = .windowBackgroundColor
        isReleasedWhenClosed = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.documentView = list
        outer.autoresizingMask = [.width, .height]
        inner.autoresizingMask = [.width, .height]
        scroll.autoresizingMask = [.width, .height]
        contentView = outer
        outer.addSubview(inner)
        inner.addSubview(scroll)
        editWidgets.isBordered = false
        editWidgets.setAccessibilityIdentifier("widget-editor-button")
        editWidgets.setAccessibilityLabel("Edit Widgets")
        outer.addSubview(editWidgets)
    }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .systemDialog }

    func show(_ notifications: [DemoPresentedNotification]) {
        guard notifications != shown else { return }
        shown = notifications
        for view in list.subviews { view.removeFromSuperview() }
        var top: CGFloat = 0
        for (index, notification) in notifications.enumerated() {
            if index > 0 { top += Self.rowGap }
            let card = NotificationView(
                frame: NSRect(origin: CGPoint(x: 0, y: top), size: Self.cardSize),
                notification: notification
            ) { [onAction] action in
                onAction(action, notification.id, notification.item.isCollapsedStack)
            }
            list.addSubview(card)
            top += Self.cardSize.height + Self.layers(notification)
        }
        resize(height: max(top, 1))
    }

    private static func layers(_ notification: DemoPresentedNotification) -> CGFloat {
        CGFloat(min(notification.hiddenMembers, StackExtent.maxLayers)) * StackExtent.layerHeight
    }

    private func resize(height: CGFloat) {
        guard let screen = NSScreen.main?.frame else { return }
        let size = CGSize(width: Self.cardSize.width, height: height)
        setFrame(
            NSRect(
                x: screen.maxX - Self.rightInset - size.width,
                y: screen.maxY - Self.topInset - size.height,
                width: size.width, height: size.height),
            display: true)
        for view in [outer, inner, scroll] as [NSView] {
            view.frame = NSRect(origin: .zero, size: size)
        }
        list.frame = NSRect(origin: .zero, size: size)
    }
}

final class GroupView: NSView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
