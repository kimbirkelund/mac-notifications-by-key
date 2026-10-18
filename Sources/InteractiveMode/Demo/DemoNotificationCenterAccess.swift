import AppKit
import NotificationAX
import NotificationCore

public final class DemoNotificationCenterAccess: NotificationCenterAccess, @unchecked Sendable {
    static let boxSize = CGSize(width: 360, height: 80)
    static let rightInset: CGFloat = 16
    static let firstTop: CGFloat = 60
    static let gap: CGFloat = 10

    private let lock = NSLock()
    private var notifications: [DemoNotification]
    private let screenFrame: CGRect

    /// `screenFrame` is in CG coordinates (top-left origin of the primary display).
    public init(notifications: [DemoNotification], screenFrame: CGRect) {
        self.notifications = notifications
        self.screenFrame = screenFrame
    }

    public var isTrusted: Bool { true }
    public var isPanelOpen: Bool { true }
    public func notificationCenterPID() -> pid_t? { nil }
    public func setPanelOpen(_ open: Bool) throws {}

    public func read(wait: TimeInterval) throws -> [NotificationItem] {
        try readPresented().map(\.item)
    }

    public func readPresented() throws -> [PresentedNotification] {
        lock.withLock {
            notifications.enumerated().map { index, notification in
                PresentedNotification(
                    item: notification.item(index: index), frame: frame(at: index))
            }
        }
    }

    public func dismiss(index: Int) throws {
        try removeIf(index: index) { _ in true }
    }

    public func clearAll() throws {
        lock.withLock { notifications.removeAll() }
    }

    public func clearAll(forApp index: Int) throws {
        try lock.withLock {
            guard notifications.indices.contains(index) else {
                throw NbkError.indexOutOfRange(requested: index, count: notifications.count)
            }
            let app = notifications[index].app
            notifications.removeAll { $0.app == app }
        }
    }

    public func press(index: Int) throws {
        try removeIf(index: index) { $0.activateCloses }
    }

    public func perform(action displayName: String, index: Int) throws {
        try removeIf(index: index) { notification in
            guard let action = notification.actions.first(where: { $0.name == displayName })
            else {
                throw NbkError.unknownAction(
                    name: displayName, available: notification.actions.map(\.name))
            }
            return action.closes
        }
    }

    private func removeIf(index: Int, _ closes: (DemoNotification) throws -> Bool) throws {
        try lock.withLock {
            guard notifications.indices.contains(index) else {
                throw NbkError.indexOutOfRange(requested: index, count: notifications.count)
            }
            if try closes(notifications[index]) { notifications.remove(at: index) }
        }
    }

    private func frame(at index: Int) -> CGRect {
        CGRect(
            x: screenFrame.maxX - Self.rightInset - Self.boxSize.width,
            y: screenFrame.minY + Self.firstTop + CGFloat(index) * (Self.boxSize.height + Self.gap),
            width: Self.boxSize.width, height: Self.boxSize.height)
    }
}

public struct DemoMode {
    public let access: NotificationCenterAccess
    public let decorator: @MainActor ([PresentedNotification]) -> Void

    @MainActor
    public init(
        file: DemoFile, mainScreenFrame: () -> CGRect?,
        primaryScreenHeight: CGFloat? = NSScreen.screens.first?.frame.height
    ) throws {
        guard let frame = mainScreenFrame(), let primaryScreenHeight else {
            throw InteractiveError.noScreen
        }
        access = DemoNotificationCenterAccess(
            notifications: file.notifications,
            screenFrame: ScreenGeometry.cgRect(
                fromAppKit: frame, primaryScreenHeight: primaryScreenHeight))
        let decoration = DemoDecoration()
        decorator = { decoration.draw($0) }
    }
}
