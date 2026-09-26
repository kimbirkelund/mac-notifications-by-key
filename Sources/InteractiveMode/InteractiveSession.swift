import AppKit
import NotificationAX

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
        NSApp.run()
        exit(0)
    }
}

@MainActor
private final class Session {
    private let access: NotificationCenterAccess
    private var window: OverlayWindow?
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

    func teardown() {
        guard !tearingDown else { return }
        tearingDown = true
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
