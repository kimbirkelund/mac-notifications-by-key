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

final class OverlayWindow: NSWindow {
    private static let dockWindowLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.dockWindow)))

    var onKey: ((OverlayKey) -> Void)?

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
