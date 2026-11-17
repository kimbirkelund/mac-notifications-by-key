import AppKit
import DemoNotifications

@MainActor
final class DemoController: NSObject, NSApplicationDelegate {
    private let model: DemoNotificationsModel
    private let actions = DispatchQueue(label: "demo-nc.actions")
    private var window: DemoWindow?
    private var timer: Timer?
    private var statusItem: NSStatusItem?
    private var staysClosed = false
    private var signalSources: [DispatchSourceSignal] = []
    private let pending = PendingEvents()

    init(model: DemoNotificationsModel) {
        self.model = model
        model.observer = { [pending] event in pending.append(event) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = DemoWindow { [weak self] action, id, isStack in
            self?.perform(action, id: id, isStack: isStack)
        }
        self.window = window
        statusItem = makeStatusItem()
        signalSources = [
            onSignal(SIGUSR1) {
                $0.model.setListOpen(false)
                $0.staysClosed = true
            },
            onSignal(SIGUSR2) { $0.model.signal() },
        ]
        render()
        model.ready()
        publish(pending.take(through: .max))
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

    private func onSignal(_ signal: Int32, _ handle: @escaping (DemoController) -> Void)
        -> DispatchSourceSignal
    {
        Darwin.signal(signal, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                handle(self)
                self.render()
            }
        }
        source.resume()
        return source
    }

    @objc private func toggle() {
        model.setListOpen(!model.isListOpen && !staysClosed)
        render()
    }

    private func render() {
        guard let window else { return }
        model.advance()
        let snapshot = model.renderSnapshot()
        window.show(snapshot.presented)
        let isOpen = snapshot.listOpen
        if isOpen, !window.isVisible {
            window.orderFrontRegardless()
        } else if !isOpen, window.isVisible {
            window.orderOut(nil)
        }
        publish(pending.take(through: snapshot.seq))
    }

    private func publish(_ events: [DemoEvent]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for event in events {
            var line: Data
            do { line = try encoder.encode(event) } catch {
                FileHandle.standardError.write(Data("demo-nc: \(error)\n".utf8))
                continue
            }
            line.append(0x0A)
            do { try FileHandle.standardOutput.write(contentsOf: line) } catch { return }
        }
    }

    private func perform(_ action: NotificationAction, id: Int, isStack: Bool) {
        let model = model
        actions.async { [weak self] in
            do {
                switch action {
                case .press:
                    if isStack { try model.expand(id: id) } else { try model.press(id: id) }
                case .close:
                    try model.dismiss(id: id)
                case .clearAll:
                    try model.clearAll(id: id)
                case .named(let name):
                    try model.perform(action: name, id: id)
                case .submitField(let text):
                    try model.submitField(id: id, text: text)
                case .cancelField:
                    try model.cancelField(id: id)
                }
            } catch {
                if case .cancelField = action {
                    FileHandle.standardError.write(Data("demo-nc: \(error)\n".utf8))
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.render() }
            }
        }
    }
}
