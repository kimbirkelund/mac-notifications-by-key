import AppKit
import DemoNotifications

@MainActor
final class DemoController: NSObject, NSApplicationDelegate {
    private let model: DemoNotificationsModel
    private let actions = DispatchQueue(label: "demo-nc.actions")
    private var window: DemoWindow?
    private var timer: Timer?

    init(model: DemoNotificationsModel) {
        self.model = model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = DemoWindow { [weak self] action, id, isStack in
            self?.perform(action, id: id, isStack: isStack)
        }
        self.window = window
        render()
        window.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    private func render() {
        window?.show(model.presented())
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
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.render() }
            }
        }
    }
}
