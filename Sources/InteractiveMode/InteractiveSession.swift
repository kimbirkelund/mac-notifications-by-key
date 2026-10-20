import AppKit
import NotificationAX
import NotificationCore

@MainActor
public enum InteractiveSession {
    private static var session: Session?

    public static func run(
        access: NotificationCenterAccess, mainScreenFrame: () -> CGRect?,
        decorator: (@MainActor ([PresentedNotification]) -> Void)? = nil
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
        session.presentedDecorator = decorator
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
    private var ending = false
    private var terminated = false
    private var dispatching = false
    private var hasDrawn = false
    private let endingHold: TimeInterval
    private let endingFade: TimeInterval
    private let terminate: () -> Void
    var presentedDecorator: (@MainActor (_ presented: [PresentedNotification]) -> Void)?

    static let endingHold: TimeInterval = 1
    static let endingFade: TimeInterval = 0.5
    static let endingLabel = "No more jobs!"

    init(
        access: NotificationCenterAccess,
        dispatchQueue: DispatchQueue = .global(qos: .userInitiated),
        endingHold: TimeInterval = Session.endingHold,
        endingFade: TimeInterval = Session.endingFade,
        terminate: @escaping () -> Void = { exit(0) }
    ) {
        self.access = access
        self.dispatchQueue = dispatchQueue
        self.endingHold = endingHold
        self.endingFade = endingFade
        self.terminate = terminate
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
                read: { (try? access.readPresented()) ?? [] },
                isReady: { access.isPanelOpen },
                emptyAgreement: Self.presentedEmptyAgreement,
                deadline: Date().addingTimeInterval(Self.presentedReadTimeout))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.refreshActionPanels(with: presented) }
            }
        }
    }

    private nonisolated static let presentedReadTimeout: TimeInterval = 1
    private nonisolated static let presentedReadInterval: TimeInterval = 0.15
    private nonisolated static let presentedEmptyAgreement = 2
    private static let refreshInterval: TimeInterval = 0.5

    /// The panel fills in over several reads and its rows slide into place, so a
    /// non-empty read counts only once the next one agrees with it. An empty read
    /// counts only once the panel is ready and enough consecutive reads agree.
    nonisolated static func settledPresented(
        read: () -> [PresentedNotification],
        isReady: () -> Bool,
        emptyAgreement: Int,
        deadline: Date,
        interval: TimeInterval = presentedReadInterval,
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) -> [PresentedNotification] {
        var previous: [PresentedNotification]?
        var readyEmptyReads = 0
        while true {
            let ready = isReady()
            let current = read()
            if !current.isEmpty, current == previous { return current }
            readyEmptyReads = ready && current.isEmpty ? readyEmptyReads + 1 : 0
            if readyEmptyReads >= emptyAgreement { return current }
            if now() >= deadline { return current }
            previous = current
            sleep(interval)
        }
    }

    func handle(_ key: OverlayKey) {
        if key == .escape { return teardown() }
        guard !ending else { return }
        if case .character(let character) = key,
            let global = GlobalCommand.resolve(key: character)
        {
            return dispatchGlobal(global)
        }
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
                key: key, entries: ActionPanelLayout.entries(for: item))
        else { return }
        dispatch { access in
            switch command {
            case .activate:
                if item.isCollapsedStack {
                    try access.expand(index: item.index)
                } else {
                    try access.press(index: item.index)
                }
            case .dismiss: try access.dismiss(index: item.index)
            case .action(let name): try access.perform(action: name, index: item.index)
            }
        }
    }

    private func dispatchGlobal(_ command: GlobalCommand) {
        guard !dispatching else { return }
        switch command {
        case .clearAll:
            dispatch { try $0.clearAll() }
        case .dismissAllForApp:
            guard let selected = selection.selectedIndex,
                drawnPresented.indices.contains(selected)
            else { return }
            let index = drawnPresented[selected].item.index
            dispatch { try $0.clearAll(forApp: index) }
        }
    }

    private func dispatch(_ work: @escaping (NotificationCenterAccess) throws -> Void) {
        dispatching = true
        nonisolated(unsafe) let access = access
        nonisolated(unsafe) let work = work
        dispatchQueue.async {
            do {
                try work(access)
            } catch {
                Self.reportError(error)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.dispatching = false
                    self.readNow()
                }
            }
        }
    }

    private nonisolated static func reportError(_ error: Error) {
        let message = (error as? NbkError)?.message ?? "\(error)"
        FileHandle.standardError.write(Data("nbk: \(message)\n".utf8))
    }

    private func refreshActionPanels(with presented: [PresentedNotification]?) {
        guard !tearingDown, !ending else { return }
        redraw(with: presented)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshInterval) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRead() }
        }
    }

    private func redraw(with presented: [PresentedNotification]?) {
        if let presented = presented.map(PresentedNotification.topDown),
            presented != drawnPresented || !hasDrawn
        {
            drawActionPanels(presented)
        }
    }

    private func scheduleRead() {
        read { $0.refreshActionPanels(with: $1) }
    }

    private func readNow() {
        read { session, presented in
            guard !session.tearingDown, !session.ending else { return }
            session.redraw(with: presented)
        }
    }

    private func read(then apply: @escaping (Session, [PresentedNotification]?) -> Void) {
        guard !tearingDown, !ending else { return }
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
        selection = selection.following(previous: drawnPresented, current: presented)
        drawnPresented = presented
        hasDrawn = true
        presentedDecorator?(presented)
        if presented.isEmpty, !ending, !tearingDown { beginEnding() }
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
            ActionPanelLayout.panel(for: presented, selectedIndex: selection.selectedIndex),
            primaryScreenHeight: primary.frame.height)
    }

    private func beginEnding() {
        ending = true
        window?.showEndingLabel(Self.endingLabel)
        DispatchQueue.main.asyncAfter(deadline: .now() + endingHold) { [weak self] in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
    }

    private func fadeOut() {
        guard !tearingDown else { return }
        guard let window else { return teardown() }
        window.fadeOut(duration: endingFade) { [weak self] in
            MainActor.assumeIsolated { self?.teardown() }
        }
    }

    func teardown() {
        guard !terminated else { return }
        terminated = true
        releaseScreen()
        terminate()
    }

    func releaseScreen() {
        guard !tearingDown else { return }
        tearingDown = true
        panelsWindow?.orderOut(nil)
        window?.orderOut(nil)
        do {
            try access.setPanelOpen(false)
        } catch {
            Self.reportError(error)
        }
    }
}
