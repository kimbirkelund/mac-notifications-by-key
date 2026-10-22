import AppKit
import NotificationCore
import SwiftUI

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

struct PanelVisibility {
    private(set) var isShown = false
    private var generation = 0

    mutating func show() -> Bool {
        defer { isShown = true }
        generation += 1
        return isShown
    }

    mutating func hide() -> Int? {
        guard isShown else { return nil }
        isShown = false
        generation += 1
        return generation
    }

    func isStillHidden(since hide: Int) -> Bool {
        hide == generation
    }
}

final class ActionPanelsWindow: NSWindow {
    private static let haloInset: CGFloat = 8
    private static let tint = NSColor.white.withAlphaComponent(0.22)
    private static let haloRadius: CGFloat = 16
    private static let panelRadius: CGFloat = 10
    private static let fillet: CGFloat = 8
    static let fade: TimeInterval = 0.2
    static let move: TimeInterval = 0.1
    private var glassHost: NSView?
    private var panelView: ActionPanelView?
    private var haloView: NSView?
    private var blurView: NSVisualEffectView?
    private var visibility = PanelVisibility()
    private var fadeOutWaiters: [() -> Void] = []

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

    func show(
        _ panel: ActionPanelSpec?, primaryScreenHeight: CGFloat,
        then completion: @escaping () -> Void = {}
    ) {
        guard let content = contentView else { return completion() }
        guard let panel else {
            guard let hide = visibility.hide() else {
                if content.subviews.isEmpty { return completion() }
                return fadeOutWaiters.append(completion)
            }
            panelView?.isWithdrawn = true
            fadeOutWaiters.append(completion)
            fadeAlpha(to: 0) { [weak self] in
                guard let self, visibility.isStillHidden(since: hide) else { return }
                for view in content.subviews { view.removeFromSuperview() }
                let waiters = fadeOutWaiters
                fadeOutWaiters = []
                for waiter in waiters { waiter() }
            }
            return
        }

        let attached = !content.subviews.isEmpty
        if !attached { alphaValue = 0 }
        let duration = attached ? Self.duration(Self.move, reduceMotion: Self.reduceMotion) : 0
        let wasShown = visibility.show()
        let panelView: ActionPanelView
        if let existing = self.panelView {
            panelView = existing
            panelView.apply(spec: panel)
        } else {
            panelView = ActionPanelView(spec: panel)
            self.panelView = panelView
        }
        panelView.isWithdrawn = false
        let local = { (cg: CGRect) in
            ScreenGeometry.local(
                ScreenGeometry.appKitRect(fromCG: cg, primaryScreenHeight: primaryScreenHeight),
                in: self.frame)
        }
        let size = panelView.contentSize
        let haloBottom = panel.coveredHeight + Self.haloInset
        let panelHeight = max(size.height + Self.haloInset, haloBottom)
        let panelCG = ActionPanelLayout.frame(
            anchor: panel.anchor, contentSize: CGSize(width: size.width, height: panelHeight))
        let haloRight = panel.anchor.insetBy(dx: -Self.haloInset, dy: -Self.haloInset)
        let haloCG = CGRect(
            x: panelCG.minX, y: haloRight.minY, width: haloRight.maxX - panelCG.minX,
            height: haloBottom + Self.haloInset)
        let panelFrame = local(panelCG)
        let haloFrame = local(haloCG)

        if #available(macOS 26, *) {
            let windowTop = primaryScreenHeight - frame.maxY
            let shape = GlassOutlineShape(
                halo: haloCG.offsetBy(dx: -frame.minX, dy: -windowTop),
                panel: panelCG.offsetBy(dx: -frame.minX, dy: -windowTop),
                haloRadius: Self.haloRadius, panelRadius: Self.panelRadius, fillet: Self.fillet)
            let outline = GlassOutlineView(shape: shape, tint: Color(nsColor: Self.tint))
            let hosting: NSHostingView<GlassOutlineView>
            if let existing = glassHost as? NSHostingView<GlassOutlineView> {
                hosting = existing
                withAnimation(duration > 0 ? .linear(duration: duration) : nil) {
                    hosting.rootView = outline
                }
            } else {
                hosting = NSHostingView(rootView: outline)
                hosting.sizingOptions = []
                glassHost = hosting
            }
            hosting.frame = content.bounds
            if hosting.superview == nil { content.addSubview(hosting) }
            Self.animate(duration) { panelView.frame = panelFrame }
            if panelView.superview == nil {
                content.addSubview(panelView, positioned: .above, relativeTo: hosting)
            }
        } else {
            let halo = haloView ?? Self.makeHaloView()
            haloView = halo
            if halo.superview == nil { content.addSubview(halo) }

            let blur = blurView ?? Self.makeBlurView()
            blurView = blur
            Self.animate(duration) {
                halo.frame = haloFrame
                blur.frame = panelFrame
                panelView.frame = CGRect(origin: .zero, size: panelFrame.size)
            }
            if panelView.superview == nil { blur.addSubview(panelView) }
            if blur.superview == nil {
                content.addSubview(blur, positioned: .above, relativeTo: halo)
            }
        }
        if !wasShown { fadeAlpha(to: 1) }
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func fadeAlpha(to alpha: CGFloat, then completion: @escaping () -> Void = {}) {
        let duration = Self.duration(Self.fade, reduceMotion: Self.reduceMotion)
        guard duration > 0 else {
            alphaValue = alpha
            return completion()
        }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = duration
                self.animator().alphaValue = alpha
            }, completionHandler: completion)
    }

    static func duration(_ duration: TimeInterval, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : duration
    }

    private static func animate(_ duration: TimeInterval, _ changes: () -> Void) {
        guard duration > 0 else { return changes() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            changes()
        }
    }

    private static func makeHaloView() -> NSView {
        let halo = NSView()
        halo.wantsLayer = true
        halo.layer?.cornerRadius = haloRadius
        halo.layer?.borderWidth = 1
        halo.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        return halo
    }

    private static func makeBlurView() -> NSVisualEffectView {
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = panelRadius
        blur.layer?.masksToBounds = true
        return blur
    }
}

private final class ActionPanelView: NSView {
    private static let padding: CGFloat = 8
    private static let verticalPadding: CGFloat = 4
    private static let rowSpacing: CGFloat = 2
    private static let activatorGap: CGFloat = 6
    private static let hintGap: CGFloat = 8
    private static let hintGlyphs = ["▲", "▼", "j", "k"]

    private var rows: [(activator: NSTextField, entry: NSTextField)] = []
    private var topHints: [NSTextField] = []
    private var bottomHints: [NSTextField] = []
    private var activatorWidth: CGFloat = 0
    private var hintWidth: CGFloat = 0
    private var coveredHeight: CGFloat = 0
    private(set) var contentSize: CGSize = .zero

    init(spec: ActionPanelSpec) {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("action-panel")
        setAccessibilitySelected(true)
        apply(spec: spec)
        frame = CGRect(origin: .zero, size: contentSize)
    }

    required init?(coder: NSCoder) { nil }

    var isWithdrawn = false {
        didSet { setAccessibilityElement(!isWithdrawn) }
    }

    override func accessibilityChildren() -> [Any]? {
        isWithdrawn ? [] : super.accessibilityChildren()
    }

    func apply(spec: ActionPanelSpec) {
        for view in subviews { view.removeFromSuperview() }
        coveredHeight = spec.coveredHeight
        rows = spec.rowLabels.map { labels in
            (
                activator: Self.label(labels.activator, identifier: "activator", color: .modeGreen),
                entry: Self.label(labels.entry, identifier: "entry")
            )
        }
        topHints = spec.canMoveUp ? Self.hints("▲", "k") : []
        bottomHints = spec.canMoveDown ? Self.hints("j", "▼") : []
        activatorWidth = rows.map(\.activator.fittingSize.width).max() ?? 0
        hintWidth = Self.hintGlyphs.map { Self.hint($0).fittingSize.width }.max() ?? 0
        let entryWidth = rows.map(\.entry.fittingSize.width).max() ?? 0
        let rowHeights = rows.map(Self.rowHeight)
        let hintHeight = (topHints + bottomHints).map { $0.fittingSize.height + Self.rowSpacing }
            .reduce(0, +)
        contentSize = CGSize(
            width: 2 * Self.padding + activatorWidth + Self.activatorGap + entryWidth
                + Self.hintGap + hintWidth,
            height: 2 * Self.verticalPadding
                + max(
                    rowHeights.reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * Self.rowSpacing,
                    hintHeight))
        for row in rows {
            addSubview(row.activator)
            addSubview(row.entry)
        }
        for hint in topHints + bottomHints { addSubview(hint) }
        place()
    }

    override var frame: NSRect {
        didSet { place() }
    }

    private func place() {
        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = false
            layOut()
        }
    }

    private func layOut() {
        let hintX = bounds.width - Self.padding - hintWidth
        var top = bounds.height - Self.verticalPadding
        for row in rows {
            let height = Self.rowHeight(row)
            top -= height
            row.activator.frame = NSRect(
                x: Self.padding, y: top, width: activatorWidth, height: height)
            let entryX = Self.padding + activatorWidth + Self.activatorGap
            row.entry.frame = NSRect(
                x: entryX, y: top, width: hintX - Self.hintGap - entryX, height: height)
            top -= Self.rowSpacing
        }

        top = bounds.height - Self.verticalPadding
        for hint in topHints {
            let height = hint.fittingSize.height
            top -= height
            hint.frame = NSRect(x: hintX, y: top, width: hintWidth, height: height)
            top -= Self.rowSpacing
        }

        let stacked = bottomHints.map { $0.fittingSize.height + Self.rowSpacing }.reduce(0, +)
        var bottom = min(
            bounds.height - coveredHeight + Self.verticalPadding,
            top + Self.rowSpacing - stacked)
        for hint in bottomHints.reversed() {
            let height = hint.fittingSize.height
            hint.frame = NSRect(x: hintX, y: bottom, width: hintWidth, height: height)
            bottom += height + Self.rowSpacing
        }
    }

    private static func rowHeight(_ row: (activator: NSTextField, entry: NSTextField)) -> CGFloat {
        max(row.activator.fittingSize.height, row.entry.fittingSize.height)
    }

    private static func hints(_ glyphs: String...) -> [NSTextField] {
        glyphs.map(hint)
    }

    private static func hint(_ glyph: String) -> NSTextField {
        let hint = label(glyph, identifier: "hint", color: .modeGreen)
        hint.alignment = .center
        return hint
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
