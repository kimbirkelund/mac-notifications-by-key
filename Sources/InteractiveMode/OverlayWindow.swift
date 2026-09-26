import AppKit

final class OverlayWindow: NSWindow {
    private static let escapeKeyCode: UInt16 = 53
    private static let dockWindowLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.dockWindow)))

    var onEscape: (() -> Void)?

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = Self.dockWindowLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .black
        alphaValue = 0.35
        ignoresMouseEvents = false
        hasShadow = false
        isReleasedWhenClosed = false
        title = "Notifications"

        let label = NSTextField(labelWithString: "Notifications")
        label.font = .systemFont(ofSize: 64, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == Self.escapeKeyCode { onEscape?() }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
