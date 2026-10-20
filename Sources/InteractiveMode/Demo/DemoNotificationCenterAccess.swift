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
    private let now: () -> Date
    private let start: Date

    /// `screenFrame` is in CG coordinates (top-left origin of the primary display).
    public init(
        notifications: [DemoNotification], screenFrame: CGRect,
        now: @escaping () -> Date = Date.init
    ) {
        self.notifications = notifications
        self.screenFrame = screenFrame
        self.now = now
        self.start = now()
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
            presentedSlots().enumerated().map { index, slot in
                PresentedNotification(
                    item: slot.notification.item(index: index), frame: frame(at: index))
            }
        }
    }

    public func dismiss(index: Int) throws {
        try removeIf(index: index) { _ in true }
    }

    public func clearAll() throws {
        lock.withLock {
            let positions = Set(presentedSlots().map(\.position))
            notifications = notifications.enumerated()
                .filter { !positions.contains($0.offset) }.map(\.element)
        }
    }

    public func clearAll(forApp index: Int) throws {
        try lock.withLock {
            let slots = presentedSlots()
            guard slots.indices.contains(index) else {
                throw NbkError.indexOutOfRange(requested: index, count: slots.count)
            }
            let app = slots[index].notification.app
            let positions = Set(slots.filter { $0.notification.app == app }.map(\.position))
            notifications = notifications.enumerated()
                .filter { !positions.contains($0.offset) }.map(\.element)
        }
    }

    public func expand(index: Int) throws {
        try lock.withLock {
            let slots = presentedSlots()
            guard slots.indices.contains(index) else {
                throw NbkError.indexOutOfRange(requested: index, count: slots.count)
            }
            let (position, stack) = slots[index]
            guard stack.isCollapsedStack else {
                throw NbkError.unknownAction(
                    name: "Expand", available: stack.actions.map(\.name))
            }
            notifications.replaceSubrange(
                position...position,
                with: stack.members.map {
                    var member = $0
                    member.leavesAfter = stack.leavesAfter
                    return member
                })
        }
    }

    public func press(index: Int) throws {
        try removeIf(index: index) { notification in
            guard !notification.isCollapsedStack else {
                throw NbkError.unknownAction(
                    name: "Activate", available: notification.actions.map(\.name))
            }
            return notification.activateCloses
        }
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
        let removal = try lock.withLock { () -> (position: Int, takes: TimeInterval)? in
            let slots = presentedSlots()
            guard slots.indices.contains(index) else {
                throw NbkError.indexOutOfRange(requested: index, count: slots.count)
            }
            let (position, notification) = slots[index]
            return try closes(notification) ? (position, notification.takes ?? 0) : nil
        }
        guard let removal else { return }
        if removal.takes > 0 { Thread.sleep(forTimeInterval: removal.takes) }
        lock.withLock { _ = notifications.remove(at: removal.position) }
    }

    private func presentedSlots() -> [(position: Int, notification: DemoNotification)] {
        let elapsed = now().timeIntervalSince(start)
        return notifications.enumerated().compactMap { position, notification in
            let arrived = elapsed >= (notification.arrivesAfter ?? 0)
            let left = notification.leavesAfter.map { elapsed >= $0 } ?? false
            return arrived && !left ? (position, notification) : nil
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
