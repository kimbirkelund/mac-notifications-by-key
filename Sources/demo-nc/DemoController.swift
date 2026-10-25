import AppKit
import DemoNotifications

@MainActor
final class DemoController: NSObject, NSApplicationDelegate {
    private let model: DemoNotificationsModel
    private let actions = DispatchQueue(label: "demo-nc.actions")
    private var window: DemoWindow?
    private var timer: Timer?
    private var statusItem: NSStatusItem?
    private var isOpen: Bool

    init(model: DemoNotificationsModel, isOpen: Bool) {
        self.model = model
        self.isOpen = isOpen
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = DemoWindow { [weak self] action, id, isStack in
            self?.perform(action, id: id, isStack: isStack)
        }
        self.window = window
        statusItem = makeStatusItem()
        render()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "Demo NC"
            button.setAccessibilityIdentifier("demo-nc-toggle")
            button.setAccessibilityLabel("Demo notifications")
            button.target = self
            button.action = #selector(toggle)
        }
        return item
    }

    @objc private func toggle() {
        isOpen.toggle()
        render()
    }

    private func render() {
        guard let window else { return }
        window.show(model.presented())
        if isOpen, !window.isVisible {
            window.orderFrontRegardless()
        } else if !isOpen, window.isVisible {
            window.orderOut(nil)
        }
    }

    private func perform(_ action: NotificationAction, id: Int, isStack: Bool) {
        let model = model
        actions.async { [weak self] in
            switch action {
            case .press:
                try? isStack ? model.expand(id: id) : model.press(id: id)
            case .close, .clearAll:
                try? model.dismiss(id: id)
            case .named(let name):
                try? model.perform(action: name, id: id)
            case .submitField:
                try? model.submitField(id: id)
            case .cancelField:
                try? model.cancelField(id: id)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.render() }
            }
        }
    }
}
