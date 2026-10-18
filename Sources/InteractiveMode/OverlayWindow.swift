import AppKit
import NotificationCore

enum OverlayKey: Equatable {
    case escape, up, down
    case character(String)

    private static let escapeKeyCode: UInt16 = 53
    private static let downKeyCode: UInt16 = 125
    private static let upKeyCode: UInt16 = 126

    private static let privateUse: ClosedRange<UInt32> = 0xE000...0xF8FF

    init?(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) {
        guard modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }
        switch keyCode {
        case Self.escapeKeyCode: self = .escape
        case Self.upKeyCode: self = .up
        case Self.downKeyCode: self = .down
        default:
            guard let characters, characters.count == 1,
                !characters.unicodeScalars.contains(where: { Self.privateUse.contains($0.value) })
            else { return nil }
            self = .character(
                modifiers.contains(.shift) ? characters.uppercased() : characters.lowercased())
        }
    }
}

extension OverlayKey {
    var selectionMove: SelectionMove? {
        switch self {
        case .down, .character("j"): .down
        case .up, .character("k"): .up
        default: nil
        }
    }
}

final class FarewellWindow: NSWindow {
    private let label = NSTextField(labelWithString: "")

    init(frame: CGRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        title = "Farewell"

        label.font = .systemFont(ofSize: 64, weight: .semibold)
        label.textColor = NSColor(red: 0.1, green: 0.65, blue: 0.25, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.cgColor
        box.layer?.borderColor = NSColor.lightGray.cgColor
        box.layer?.borderWidth = 3
        box.layer?.cornerRadius = 24
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.addSubview(box)
        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -40),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 20),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -20),
        ])
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ text: String) {
        label.stringValue = text
    }
}

final class OverlayWindow: NSWindow {
    private static let dockWindowLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.dockWindow)))

    var onKey: ((OverlayKey) -> Void)?
    private var farewell: FarewellWindow?

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
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
    }

    func showEndingLabel(_ text: String) {
        let farewell = FarewellWindow(frame: frame, level: level)
        farewell.show(text)
        addChildWindow(farewell, ordered: .above)
        farewell.orderFront(nil)
        self.farewell = farewell
    }

    func fadeOut(duration: TimeInterval, completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = duration
                self.animator().alphaValue = 0
                self.farewell?.animator().alphaValue = 0
            }, completionHandler: completion)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard
            let key = OverlayKey(
                keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                modifiers: event.modifierFlags)
        else { return }
        onKey?(key)
    }

    override func cancelOperation(_ sender: Any?) {
        onKey?(.escape)
    }
}
