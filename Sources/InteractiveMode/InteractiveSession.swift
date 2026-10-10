import AppKit
import NotificationAX
import NotificationCore

@MainActor
public enum InteractiveSession {
    private static var session: Session?

    public static func run(
        access: NotificationCenterAccess, mainScreenFrame: () -> CGRect?
    ) throws -> Never {
        guard let frame = mainScreenFrame() else { throw InteractiveError.noScreen }

        let lock = InstanceLock.acquire()
        if case .focusExisting(let pid) = InstanceDecision(
            lockAcquired: lock.acquired, ownerPID: lock.ownerPID)
        {
            if let pid {
                NSRunningApplication(processIdentifier: pid)?
                    .activate(options: .activateIgnoringOtherApps)
            }
            exit(0)
        }

        let session = Session(access: access)
        Self.session = session
        session.installSignalHandlers()
        do {
            try access.setPanelOpen(true)
        } catch {
            try? access.setPanelOpen(false)
            throw error
        }
        session.showOverlay(frame: frame)
        session.showActionPanels()
        NSApp.run()
        exit(0)
    }
}

@MainActor
final class Session {
    private let access: NotificationCenterAccess
    private let dispatchQueue: DispatchQueue
    private var window: OverlayWindow?
    private var panelsWindow: ActionPanelsWindow?
    private var drawnPresented: [PresentedNotification] = []
    private var selection = SelectionState.initial(count: 0)
    private var signalSources: [DispatchSourceSignal] = []
    private var tearingDown = false
    private var dispatching = false

    init(
        access: NotificationCenterAccess,
        dispatchQueue: DispatchQueue = .global(qos: .userInitiated)
    ) {
        self.access = access
        self.dispatchQueue = dispatchQueue
    }

    /// Installed before the panel opens so a signal during setup still closes it: the
    /// sources record the signal and fire once the run loop starts.
    func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.teardown() }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func showOverlay(frame: CGRect) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = OverlayWindow(frame: frame)
        window.onKey = { [weak self] key in self?.handle(key) }
        self.window = window
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
    }

    func showActionPanels() {
        nonisolated(unsafe) let access = access
        DispatchQueue.global(qos: .userInitiated).async {
            let presented = Self.settledPresented(
                access, deadline: Date().addingTimeInterval(Self.presentedReadTimeout))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.refreshActionPanels(with: presented) }
            }
        }
    }

    private nonisolated static let presentedReadTimeout: TimeInterval = 1
    private nonisolated static let presentedReadInterval: TimeInterval = 0.15
    private static let refreshInterval: TimeInterval = 0.5
    private static let panelWidth: CGFloat = 260

    /// The panel fills in over several reads and its rows slide into place, so a
    /// non-empty read counts only once the next one agrees with it.
    private nonisolated static func settledPresented(
        _ access: NotificationCenterAccess, deadline: Date
    ) -> [PresentedNotification] {
        var previous: [PresentedNotification]?
        while true {
            let current = (try? access.readPresented()) ?? []
            if !current.isEmpty, current == previous { return current }
            if Date() >= deadline { return current }
            previous = current
            Thread.sleep(forTimeInterval: presentedReadInterval)
        }
    }

    func handle(_ key: OverlayKey) {
        if key == .escape { return teardown() }
        if let move = key.selectionMove {
            let before = selection
            selection.apply(move)
            if selection != before { drawActionPanels(drawnPresented) }
        } else if case .character(let character) = key {
            dispatchEntry(forKey: character)
        }
    }

    private func dispatchEntry(forKey key: String) {
        guard !dispatching, let selected = selection.selectedIndex,
            drawnPresented.indices.contains(selected)
        else { return }
        let item = drawnPresented[selected].item
        guard
            let command = EntryCommand.resolve(
                key: key, entries: ActionPanelLayout.builtInEntries + item.actions)
        else { return }
        dispatching = true
        nonisolated(unsafe) let access = access
        dispatchQueue.async {
            Self.run(command, on: item.index, access)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.dispatching = false
                    self.readNow()
                }
            }
        }
    }

    private nonisolated static func run(
        _ command: EntryCommand, on index: Int, _ access: NotificationCenterAccess
    ) {
        do {
            switch command {
            case .activate: try access.press(index: index)
            case .dismiss: try access.dismiss(index: index)
            case .action(let name): try access.perform(action: name, index: index)
            }
        } catch {
            reportError(error)
        }
    }

    private nonisolated static func reportError(_ error: Error) {
        let message = (error as? NbkError)?.message ?? "\(error)"
        FileHandle.standardError.write(Data("nbk: \(message)\n".utf8))
    }

    private func refreshActionPanels(with presented: [PresentedNotification]?) {
        guard !tearingDown else { return }
        redraw(with: presented)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshInterval) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRead() }
        }
    }

    private func redraw(with presented: [PresentedNotification]?) {
        if let presented = presented.map(PresentedNotification.topDown), presented != drawnPresented
        {
            drawActionPanels(presented)
        }
    }

    private func scheduleRead() {
        read { $0.refreshActionPanels(with: $1) }
    }

    private func readNow() {
        read { session, presented in
            guard !session.tearingDown else { return }
            session.redraw(with: presented)
        }
    }

    private func read(then apply: @escaping (Session, [PresentedNotification]?) -> Void) {
        guard !tearingDown else { return }
        nonisolated(unsafe) let access = access
        nonisolated(unsafe) let apply = apply
        DispatchQueue.global(qos: .userInitiated).async {
            let presented = try? access.readPresented()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { apply(self, presented) }
            }
        }
    }

    func drawActionPanels(_ presented: [PresentedNotification]) {
        drawnPresented = presented
        selection = selection.clamped(to: presented.count)
        guard let window, let primary = NSScreen.screens.first else { return }
        let panels: ActionPanelsWindow
        if let existing = panelsWindow {
            panels = existing
        } else {
            guard !presented.isEmpty else { return }
            panels = ActionPanelsWindow(frame: window.frame, level: window.level)
            panelsWindow = panels
            window.addChildWindow(panels, ordered: .above)
            panels.orderFront(nil)
        }
        panels.show(
            ActionPanelLayout.panels(
                for: presented, selectedIndex: selection.selectedIndex, width: Self.panelWidth),
            primaryScreenHeight: primary.frame.height)
    }

    func teardown() {
        guard !tearingDown else { return }
        tearingDown = true
        panelsWindow?.orderOut(nil)
        window?.orderOut(nil)
        do {
            try access.setPanelOpen(false)
        } catch {
            Self.reportError(error)
        }
        exit(0)
    }
}
