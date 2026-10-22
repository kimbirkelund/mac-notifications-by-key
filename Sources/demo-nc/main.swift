import AppKit

final class NotificationGroupView: NSView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    @available(macOS, deprecated: 10.10)
    override func accessibilityActionNames() -> [NSAccessibility.Action] {
        [
            .press, NSAccessibility.Action(rawValue: "Close"),
            NSAccessibility.Action(rawValue: "Name:Reply"),
        ]
    }

    @available(macOS, deprecated: 10.10)
    override func accessibilityPerformAction(_ action: NSAccessibility.Action) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Demo notifications"
        let group = NotificationGroupView(frame: NSRect(x: 10, y: 10, width: 340, height: 100))
        window.contentView?.addSubview(group)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
