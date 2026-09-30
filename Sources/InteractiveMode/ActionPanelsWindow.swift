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
                ActionPanelView(frame: ScreenGeometry.local(screenRect, in: frame), spec: spec))
        }
    }
}

private final class ActionPanelView: NSView {
    private static let padding: CGFloat = 6
    private static let spacing: CGFloat = 2
    private static let activatorGap: CGFloat = 4
    private static let columns = 2
    private static let borderWidth: CGFloat = 2

    init(frame: CGRect, spec: ActionPanelSpec) {
        super.init(frame: frame)
        clipsToBounds = true
        wantsLayer = true
        layer?.cornerRadius = 10
        if spec.isSelected {
            layer?.backgroundColor = NSColor(white: 0.24, alpha: 0.95).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = Self.borderWidth
        } else {
            layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.92).cgColor
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("action-panel")
        setAccessibilitySelected(spec.isSelected)

        let keys: [String?] =
            spec.activators ?? Array(repeating: nil, count: spec.entries.count)
        let cells = zip(spec.entries, keys).map { entry, key in
            (
                entry: Self.label(entry, identifier: "entry"),
                activator: key.map {
                    Self.label($0, identifier: "activator", color: .controlAccentColor)
                }
            )
        }
        let activatorWidth = cells.compactMap(\.activator?.intrinsicContentSize.width).max() ?? 0
        let columnWidth =
            (frame.width - 2 * Self.padding - CGFloat(Self.columns - 1) * Self.spacing)
            / CGFloat(Self.columns)
        var top = frame.height - Self.padding
        for row in stride(from: 0, to: cells.count, by: Self.columns) {
            let rowCells = cells[row..<min(row + Self.columns, cells.count)]
            let height = rowCells.map(\.entry.intrinsicContentSize.height).max() ?? 0
            top -= height
            for (column, cell) in rowCells.enumerated() {
                var x = Self.padding + CGFloat(column) * (columnWidth + Self.spacing)
                var width = columnWidth
                if let activator = cell.activator {
                    activator.frame = NSRect(x: x, y: top, width: activatorWidth, height: height)
                    addSubview(activator)
                    x += activatorWidth + Self.activatorGap
                    width -= activatorWidth + Self.activatorGap
                }
                cell.entry.frame = NSRect(x: x, y: top, width: width, height: height)
                addSubview(cell.entry)
            }
            top -= Self.spacing
        }
    }

    required init?(coder: NSCoder) { nil }

    private static func label(
        _ text: String, identifier: String, color: NSColor = .white
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityIdentifier(identifier)
        return label
    }
}
