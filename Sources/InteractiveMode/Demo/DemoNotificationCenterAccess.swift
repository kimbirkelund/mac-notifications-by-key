import AppKit
import DemoNotifications
import NotificationAX
import NotificationCore

public final class DemoNotificationCenterAccess: NotificationCenterAccess, @unchecked Sendable {
    static let boxSize = CGSize(width: 360, height: 80)
    static let rightInset: CGFloat = 16
    static let firstTop: CGFloat = 60
    static let gap: CGFloat = 10

    private let model: DemoNotificationsModel
    private let screenFrame: CGRect

    /// `screenFrame` is in CG coordinates (top-left origin of the primary display).
    public init(
        notifications: [DemoNotification], screenFrame: CGRect,
        now: @escaping () -> Date = Date.init
    ) {
        self.model = DemoNotificationsModel(notifications: notifications, now: now)
        self.screenFrame = screenFrame
    }

    public var isTrusted: Bool { true }
    public var isPanelOpen: Bool { true }
    public func notificationCenterPID() -> pid_t? { nil }
    public func setPanelOpen(_ open: Bool) throws {}

    public func read(wait: TimeInterval) throws -> [NotificationItem] {
        model.items()
    }

    public func readPresented() throws -> [PresentedNotification] {
        model.items().enumerated().map { index, item in
            PresentedNotification(item: item, frame: frame(at: index))
        }
    }

    public func dismiss(index: Int) throws { try translating { try model.dismiss(index: index) } }

    public func clearAll() throws { model.clearAll() }

    public func clearAll(forApp index: Int) throws {
        try translating { try model.clearAll(forApp: index) }
    }

    public func expand(index: Int) throws { try translating { try model.expand(index: index) } }

    public func press(index: Int) throws { try translating { try model.press(index: index) } }

    public func perform(action displayName: String, index: Int) throws {
        try translating { try model.perform(action: displayName, index: index) }
    }

    private func translating(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch let error as DemoNotificationsError {
            switch error {
            case .indexOutOfRange(let requested, let count):
                throw NbkError.indexOutOfRange(requested: requested, count: count)
            case .unknownAction(let name, let available):
                throw NbkError.unknownAction(name: name, available: available)
            }
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
