import AppKit
import DemoNotifications

enum NotificationAction: Sendable {
    case press
    case close
    case clearAll
    case named(String)

    var name: String {
        switch self {
        case .press: return "AXPress"
        case .close: return "Close"
        case .clearAll: return "Clear All"
        case .named(let name): return name
        }
    }
}

final class NotificationView: NSView {
    private static let padding: CGFloat = 10

    private let notification: DemoPresentedNotification
    private let onAction: (NotificationAction) -> Void
    private var focused = false

    init(
        frame: NSRect, notification: DemoPresentedNotification,
        onAction: @escaping (NotificationAction) -> Void
    ) {
        self.notification = notification
        self.onAction = onAction
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        addLabels()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    private func addLabels() {
        let item = notification.item
        var top = Self.padding
        for (id, text) in [("title", item.title), ("subtitle", item.subtitle), ("body", item.body)]
        {
            guard let text else { continue }
            let label = NSTextField(labelWithString: text)
            label.setAccessibilityIdentifier(id)
            if id == "title" { label.font = .boldSystemFont(ofSize: NSFont.systemFontSize) }
            let height = label.intrinsicContentSize.height
            label.frame = NSRect(
                x: Self.padding, y: top, width: frame.width - 2 * Self.padding, height: height)
            addSubview(label)
            top += height
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? {
        let item = notification.item
        return [item.app, item.title, item.subtitle, item.body].map { $0 ?? "" }
            .joined(separator: ", ")
    }

    override func isAccessibilityFocused() -> Bool { focused }
    override func setAccessibilityFocused(_ accessibilityFocused: Bool) {
        focused = accessibilityFocused
    }

    override func accessibilityPerformPress() -> Bool {
        onAction(.press)
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let item = notification.item
        let system: NotificationAction = item.isCollapsedStack ? .clearAll : .close
        return ([system] + item.actions.map(NotificationAction.named)).map { action in
            NSAccessibilityCustomAction(name: action.name) { [weak self] in
                self?.onAction(action)
                return true
            }
        }
    }
}
