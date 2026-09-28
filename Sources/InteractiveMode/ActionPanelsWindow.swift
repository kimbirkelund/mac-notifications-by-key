import AppKit
import NotificationCore

enum ScreenGeometry {
    static func appKitRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX, y: primaryScreenHeight - rect.minY - rect.height,
            width: rect.width, height: rect.height)
    }

    static func local(_ rect: CGRect, in windowFrame: CGRect) -> CGRect {
        rect.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)
    }
}

final class ActionPanelsWindow: NSWindow {
    init(frame: CGRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        alphaValue = 1
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        title = "Action panels"
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ panels: [ActionPanelSpec], primaryScreenHeight: CGFloat) {
        guard let content = contentView else { return }
        for view in content.subviews { view.removeFromSuperview() }
        for spec in panels {
            let screenRect = ScreenGeometry.appKitRect(
                fromCG: spec.frame, primaryScreenHeight: primaryScreenHeight)
            content.addSubview(
                ActionPanelView(
                    frame: ScreenGeometry.local(screenRect, in: frame), entries: spec.entries))
        }
    }
}

private final class ActionPanelView: NSView {
    private static let padding: CGFloat = 6
    private static let spacing: CGFloat = 2
    private static let columns = 2

    init(frame: CGRect, entries: [String]) {
        super.init(frame: frame)
        clipsToBounds = true
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.92).cgColor
        layer?.cornerRadius = 10
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        let columnWidth =
            (frame.width - 2 * Self.padding - CGFloat(Self.columns - 1) * Self.spacing)
            / CGFloat(Self.columns)
        var top = frame.height - Self.padding
        for row in stride(from: 0, to: entries.count, by: Self.columns) {
            let labels = entries[row..<min(row + Self.columns, entries.count)].map(Self.label)
            let height = labels.map(\.intrinsicContentSize.height).max() ?? 0
            top -= height
            for (column, label) in labels.enumerated() {
                label.frame = NSRect(
                    x: Self.padding + CGFloat(column) * (columnWidth + Self.spacing), y: top,
                    width: columnWidth, height: height)
                addSubview(label)
            }
            top -= Self.spacing
        }
    }

    required init?(coder: NSCoder) { nil }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
