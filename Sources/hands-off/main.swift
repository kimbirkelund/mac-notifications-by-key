import AppKit

final class SignPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

let arguments = CommandLine.arguments
guard arguments.count == 2, let watched = pid_t(arguments[1]) else {
    FileHandle.standardError.write(Data("usage: hands-off <pid>\n".utf8))
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let label = NSTextField(labelWithString: "Tests running — hands off")
label.font = .boldSystemFont(ofSize: 15)
label.textColor = .white
label.sizeToFit()

let padding = CGSize(width: 16, height: 8)
let size = CGSize(
    width: label.frame.width + 2 * padding.width, height: label.frame.height + 2 * padding.height)
let visible = NSScreen.main?.visibleFrame ?? .zero
let panel = SignPanel(
    contentRect: NSRect(
        x: visible.minX + 16, y: visible.minY + 16, width: size.width, height: size.height),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.title = "Hands off"
panel.level = .statusBar
panel.ignoresMouseEvents = true
panel.hidesOnDeactivate = false
panel.isOpaque = false
panel.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85)
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
label.frame.origin = CGPoint(x: padding.width, y: padding.height)
panel.contentView?.addSubview(label)
panel.orderFrontRegardless()

Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    if kill(watched, 0) != 0 && errno == ESRCH { exit(0) }
}
app.run()
