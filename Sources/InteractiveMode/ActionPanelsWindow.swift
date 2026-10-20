import AppKit
import NotificationCore
import SwiftUI

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
    private static let panelRadius: CGFloat = 10
    private static let fillet: CGFloat = 8

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
        let size = panelView.contentSize
        let overflows = size.height > panel.coveredHeight
        let bend = Self.fillet + Self.panelRadius
        let panelHeight =
            overflows
            ? max(size.height + Self.haloInset, panel.coveredHeight + bend)
            : size.height
        let haloBottom =
            overflows
            ? min(
                max(panelHeight - bend, panel.coveredHeight), panel.coveredHeight + Self.haloInset)
            : panel.coveredHeight + Self.haloInset
        let panelCG = ActionPanelLayout.frame(
            anchor: panel.anchor, contentSize: CGSize(width: size.width, height: panelHeight))
        let haloRight = panel.anchor.insetBy(dx: -Self.haloInset, dy: -Self.haloInset)
        let haloCG = CGRect(
            x: panelCG.minX, y: haloRight.minY, width: haloRight.maxX - panelCG.minX,
            height: haloBottom + Self.haloInset)
        let panelFrame = local(panelCG)
        let haloFrame = local(haloCG)

        if #available(macOS 26, *) {
            let union = haloCG.union(panelCG)
            let shape = GlassOutlineShape(
                halo: haloCG.offsetBy(dx: -union.minX, dy: -union.minY),
                panel: panelCG.offsetBy(dx: -union.minX, dy: -union.minY),
                haloRadius: Self.haloRadius, panelRadius: Self.panelRadius, fillet: Self.fillet)
            let hosting = NSHostingView(
                rootView: GlassOutlineView(shape: shape, tint: Color(nsColor: Self.tint)))
            hosting.frame = local(union)
            content.addSubview(hosting)
            panelView.frame = local(panelCG)
            content.addSubview(panelView)
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
