import AppKit
import DemoNotifications

enum NotificationAction: Sendable {
    case press
    case close
    case clearAll
    case named(String)
    case submitField
    case cancelField

    var name: String {
        switch self {
        case .press: return "AXPress"
        case .close: return "Close"
        case .clearAll: return "Clear All"
        case .named(let name): return name
        case .submitField: return "Submit"
        case .cancelField: return "Cancel"
        }
    }
}

final class NotificationView: NSView, NSTextFieldDelegate {
    private static let padding: CGFloat = 10

    private let notification: DemoPresentedNotification
    private let onAction: (NotificationAction) -> Void
    private var focused = false
    private(set) var field: NSTextField?

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
        let top = addLabels()
        if notification.showsField { addField(top: top) }
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    private func addLabels() -> CGFloat {
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
        return top
    }

    private func addField(top: CGFloat) {
        let field = NSTextField(string: "")
        field.setAccessibilityIdentifier("reply")
        field.target = self
        field.action = #selector(submitField)
        field.delegate = self
        field.cell?.sendsActionOnEndEditing = false
        let gap: CGFloat = 4
        let height = field.intrinsicContentSize.height
        field.frame = NSRect(
            x: Self.padding, y: top + gap, width: frame.width - 2 * Self.padding, height: height)
        frame.size.height += gap + height
        addSubview(field)
        self.field = field
    }

    @objc private func submitField() { onAction(.submitField) }

    override func cancelOperation(_ sender: Any?) { onAction(.cancelField) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool
    {
        guard selector == #selector(cancelOperation(_:)) else { return false }
        cancelOperation(nil)
        return true
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
