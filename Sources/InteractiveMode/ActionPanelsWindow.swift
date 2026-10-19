import AppKit
import NotificationCore

enum ScreenGeometry {
    static func appKitRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX, y: primaryScreenHeight - rect.minY - rect.height,
            width: rect.width, height: rect.height)
    }

    static func cgRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        appKitRect(fromCG: rect, primaryScreenHeight: primaryScreenHeight)
    }

    static func local(_ rect: CGRect, in windowFrame: CGRect) -> CGRect {
        rect.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)
    }
}

final class ActionPanelsWindow: NSWindow {
    private static let haloInset: CGFloat = 8
    private static let tint = NSColor.white.withAlphaComponent(0.22)
    private static let haloRadius: CGFloat = 16
    private static let panelRadius: CGFloat = 12
    private static let mergeSpacing: CGFloat = 12

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

    func show(_ panel: ActionPanelSpec?, primaryScreenHeight: CGFloat) {
        guard let content = contentView else { return }
        for view in content.subviews { view.removeFromSuperview() }
        guard let panel else { return }

        let panelView = ActionPanelView(spec: panel)
        let local = { (cg: CGRect) in
            ScreenGeometry.local(
                ScreenGeometry.appKitRect(fromCG: cg, primaryScreenHeight: primaryScreenHeight),
                in: self.frame)
        }
        let paddedContent = CGSize(
            width: panelView.contentSize.width,
            height: panelView.contentSize.height + Self.haloInset)
        let panelFrame = local(
            ActionPanelLayout.frame(anchor: panel.anchor, contentSize: paddedContent))
        let haloFrame = local(panel.anchor).insetBy(dx: -Self.haloInset, dy: -Self.haloInset)
            .union(CGRect(x: panelFrame.minX, y: panelFrame.maxY, width: 0, height: 0))

        if #available(macOS 26, *) {
            let container = NSGlassEffectContainerView(frame: content.bounds)
            container.spacing = Self.mergeSpacing
            let host = NSView(frame: content.bounds)
            container.contentView = host

            let halo = NSGlassEffectView(frame: haloFrame)
            halo.cornerRadius = Self.haloRadius
            halo.tintColor = Self.tint
            host.addSubview(halo)

            let glass = NSGlassEffectView(frame: panelFrame)
            glass.cornerRadius = Self.panelRadius
            glass.tintColor = Self.tint
            panelView.frame = glass.bounds
            glass.contentView = panelView
            host.addSubview(glass)

            content.addSubview(container)
        } else {
            let halo = NSView(frame: haloFrame)
            halo.wantsLayer = true
            halo.layer?.cornerRadius = Self.haloRadius
            halo.layer?.borderWidth = 1
            halo.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
            content.addSubview(halo)

            let blur = NSVisualEffectView(frame: panelFrame)
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = Self.panelRadius
            blur.layer?.masksToBounds = true
            panelView.frame = blur.bounds
            blur.addSubview(panelView)
            content.addSubview(blur)
        }
    }
}

private final class ActionPanelView: NSView {
    private static let padding: CGFloat = 8
    private static let rowSpacing: CGFloat = 2
    private static let activatorGap: CGFloat = 6

    private let rows: [(activator: NSTextField, entry: NSTextField)]
    private let activatorWidth: CGFloat
    let contentSize: CGSize

    init(spec: ActionPanelSpec) {
        rows = zip(spec.activatorLabels, spec.entries).map { label, entry in
            (
                activator: Self.label(label, identifier: "activator", color: .controlAccentColor),
                entry: Self.label(entry, identifier: "entry")
            )
        }
        activatorWidth = rows.map(\.activator.fittingSize.width).max() ?? 0
        let entryWidth = rows.map(\.entry.fittingSize.width).max() ?? 0
        let rowHeights = rows.map(Self.rowHeight)
        contentSize = CGSize(
            width: 2 * Self.padding + activatorWidth + Self.activatorGap + entryWidth,
            height: 2 * Self.padding + rowHeights.reduce(0, +)
                + CGFloat(max(rows.count - 1, 0)) * Self.rowSpacing)
        super.init(frame: CGRect(origin: .zero, size: contentSize))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("action-panel")
        setAccessibilitySelected(true)
        for row in rows {
            addSubview(row.activator)
            addSubview(row.entry)
        }
    }

    required init?(coder: NSCoder) { nil }

    override var frame: NSRect {
        didSet { place() }
    }

    private func place() {
        var top = bounds.height - Self.padding
        for row in rows {
            let height = Self.rowHeight(row)
            top -= height
            row.activator.frame = NSRect(
                x: Self.padding, y: top, width: activatorWidth, height: height)
            let entryX = Self.padding + activatorWidth + Self.activatorGap
            row.entry.frame = NSRect(
                x: entryX, y: top, width: bounds.width - entryX - Self.padding, height: height)
            top -= Self.rowSpacing
        }
    }

    private static func rowHeight(_ row: (activator: NSTextField, entry: NSTextField)) -> CGFloat {
        max(row.activator.fittingSize.height, row.entry.fittingSize.height)
    }

    private static func label(
        _ text: String, identifier: String, color: NSColor = .white
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.alignment = identifier == "activator" ? .right : .left
        label.setAccessibilityIdentifier(identifier)
        return label
    }
}
