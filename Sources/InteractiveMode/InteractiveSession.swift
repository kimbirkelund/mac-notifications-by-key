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
private final class Session {
    private let access: NotificationCenterAccess
    private var window: OverlayWindow?
    private var panelsWindow: ActionPanelsWindow?
    private var drawnPresented: [PresentedNotification] = []
    private var signalSources: [DispatchSourceSignal] = []
    private var tearingDown = false

    init(access: NotificationCenterAccess) {
        self.access = access
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
        window.onEscape = { [weak self] in self?.teardown() }
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

    private func refreshActionPanels(with presented: [PresentedNotification]?) {
        guard !tearingDown else { return }
        if let presented, presented != drawnPresented { drawActionPanels(presented) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshInterval) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRead() }
        }
    }

    private func scheduleRead() {
        guard !tearingDown else { return }
        nonisolated(unsafe) let access = access
        DispatchQueue.global(qos: .userInitiated).async {
            let presented = try? access.readPresented()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.refreshActionPanels(with: presented) }
            }
        }
    }

    private func drawActionPanels(_ presented: [PresentedNotification]) {
        guard let window, let primary = NSScreen.screens.first else { return }
        drawnPresented = presented
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
            ActionPanelLayout.panels(for: presented, width: Self.panelWidth),
            primaryScreenHeight: primary.frame.height)
    }

    func teardown() {
        guard !tearingDown else { return }
        tearingDown = true
        panelsWindow?.orderOut(nil)
        window?.orderOut(nil)
        do {
            try access.setPanelOpen(false)
        } catch let error as NbkError {
            FileHandle.standardError.write(Data("nbk: \(error.message)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("nbk: \(error)\n".utf8))
        }
        exit(0)
    }
}
