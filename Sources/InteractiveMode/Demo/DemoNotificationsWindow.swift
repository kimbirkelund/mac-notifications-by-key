import AppKit
import NotificationCore

@MainActor
final class DemoDecoration {
    private var window: DemoNotificationsWindow?

    func draw(_ presented: [PresentedNotification]) {
        guard let primary = NSScreen.screens.first else { return }
        if window == nil {
            guard let overlay = NSApp.windows.first(where: { $0 is OverlayWindow }) else { return }
            let created = DemoNotificationsWindow(frame: overlay.frame, level: overlay.level)
            overlay.addChildWindow(created, ordered: .above)
            created.orderFront(nil)
            window = created
        }
        window?.show(presented, primaryScreenHeight: primary.frame.height)
    }
}

final class DemoNotificationsWindow: NSWindow {
    init(frame: CGRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        title = "Demo notifications"
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ presented: [PresentedNotification], primaryScreenHeight: CGFloat) {
        guard let content = contentView else { return }
        for view in content.subviews { view.removeFromSuperview() }
        for notification in presented {
            let screenRect = ScreenGeometry.appKitRect(
                fromCG: notification.frame, primaryScreenHeight: primaryScreenHeight)
            content.addSubview(
                DemoNotificationView(
                    frame: ScreenGeometry.local(screenRect, in: frame), item: notification.item))
        }
    }
}

private final class DemoNotificationView: NSView {
    private static let padding: CGFloat = 10

    init(frame: CGRect, item: NotificationItem) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor(white: 0.85, alpha: 0.95).cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("demo-notification")

        let lines: [(String, String, NSFont)] = [
            (item.app ?? "", "app", .systemFont(ofSize: 11, weight: .regular)),
            (item.title ?? "", "title", .systemFont(ofSize: 13, weight: .semibold)),
            (
                [item.subtitle, item.body].compactMap { $0 }.joined(separator: " · "), "body",
                .systemFont(ofSize: 12, weight: .regular)
            ),
        ]
        var top = frame.height - Self.padding
        for (text, identifier, font) in lines {
            let label = NSTextField(labelWithString: text)
            label.font = font
            label.textColor = .black
            label.lineBreakMode = .byTruncatingTail
            label.setAccessibilityIdentifier(identifier)
            let height = label.intrinsicContentSize.height
            top -= height
            label.frame = NSRect(
                x: Self.padding, y: top, width: frame.width - 2 * Self.padding, height: height)
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { nil }
}
