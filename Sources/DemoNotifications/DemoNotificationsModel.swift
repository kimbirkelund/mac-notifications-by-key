import Foundation
import NotificationCore

public enum DemoNotificationsError: Error, Equatable, Sendable {
    case indexOutOfRange(requested: Int, count: Int)
    case unknownAction(name: String, available: [String])
}

public final class DemoNotificationsModel: @unchecked Sendable {
    private let lock = NSLock()
    private var notifications: [DemoNotification]
    private let now: () -> Date
    private let start: Date

    public init(notifications: [DemoNotification], now: @escaping () -> Date = Date.init) {
        self.notifications = notifications
        self.now = now
        self.start = now()
    }

    public func items() -> [NotificationItem] {
        lock.withLock {
            presentedSlots().enumerated().map { index, slot in
                slot.notification.item(index: index)
            }
        }
    }

    public func dismiss(index: Int) throws {
        try removeIf(index: index) { _ in true }
    }

    public func clearAll() {
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
                throw DemoNotificationsError.indexOutOfRange(requested: index, count: slots.count)
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
                throw DemoNotificationsError.indexOutOfRange(requested: index, count: slots.count)
            }
            let (position, stack) = slots[index]
            guard stack.isCollapsedStack else {
                throw DemoNotificationsError.unknownAction(
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
                throw DemoNotificationsError.unknownAction(
                    name: "Activate", available: notification.actions.map(\.name))
            }
            return notification.activateCloses
        }
    }

    public func perform(action displayName: String, index: Int) throws {
        try removeIf(index: index) { notification in
            guard let action = notification.actions.first(where: { $0.name == displayName })
            else {
                throw DemoNotificationsError.unknownAction(
                    name: displayName, available: notification.actions.map(\.name))
            }
            return action.closes
        }
    }

    private func removeIf(index: Int, _ closes: (DemoNotification) throws -> Bool) throws {
        let removal = try lock.withLock { () -> (position: Int, takes: TimeInterval)? in
            let slots = presentedSlots()
            guard slots.indices.contains(index) else {
                throw DemoNotificationsError.indexOutOfRange(requested: index, count: slots.count)
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
}
