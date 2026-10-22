import Foundation
import NotificationCore

public enum DemoNotificationsError: Error, Equatable, Sendable {
    case indexOutOfRange(requested: Int, count: Int)
    case unknownAction(name: String, available: [String])
    case notPresented(id: Int)
}

public struct DemoPresentedNotification: Equatable, Sendable {
    public var id: Int
    public var item: NotificationItem
    public var hiddenMembers: Int

    public init(id: Int, item: NotificationItem, hiddenMembers: Int) {
        self.id = id
        self.item = item
        self.hiddenMembers = hiddenMembers
    }
}

public final class DemoNotificationsModel: @unchecked Sendable {
    private struct Entry {
        var id: Int
        var notification: DemoNotification
    }

    private enum Target {
        case index(Int)
        case id(Int)
    }

    private let lock = NSLock()
    private var entries: [Entry]
    private var nextID: Int
    private let now: () -> Date
    private let start: Date

    public init(notifications: [DemoNotification], now: @escaping () -> Date = Date.init) {
        self.entries = notifications.enumerated().map {
            Entry(id: $0.offset, notification: $0.element)
        }
        self.nextID = notifications.count
        self.now = now
        self.start = now()
    }

    public func items() -> [NotificationItem] {
        lock.withLock {
            presentedEntries().enumerated().map { index, entry in
                entry.notification.item(index: index)
            }
        }
    }

    public func presented() -> [DemoPresentedNotification] {
        lock.withLock {
            presentedEntries().enumerated().map { index, entry in
                DemoPresentedNotification(
                    id: entry.id, item: entry.notification.item(index: index),
                    hiddenMembers: entry.notification.members.count)
            }
        }
    }

    public func dismiss(index: Int) throws { try dismiss(.index(index)) }

    public func dismiss(id: Int) throws { try dismiss(.id(id)) }

    public func clearAll() {
        lock.withLock {
            let ids = Set(presentedEntries().map(\.id))
            entries.removeAll { ids.contains($0.id) }
        }
    }

    public func clearAll(forApp index: Int) throws {
        try lock.withLock {
            let presented = presentedEntries()
            guard presented.indices.contains(index) else {
                throw DemoNotificationsError.indexOutOfRange(
                    requested: index, count: presented.count)
            }
            let app = presented[index].notification.app
            let ids = Set(presented.filter { $0.notification.app == app }.map(\.id))
            entries.removeAll { ids.contains($0.id) }
        }
    }

    public func expand(index: Int) throws { try expand(.index(index)) }

    public func expand(id: Int) throws { try expand(.id(id)) }

    public func press(index: Int) throws { try press(.index(index)) }

    public func press(id: Int) throws { try press(.id(id)) }

    public func perform(action displayName: String, index: Int) throws {
        try perform(action: displayName, .index(index))
    }

    public func perform(action displayName: String, id: Int) throws {
        try perform(action: displayName, .id(id))
    }

    private func dismiss(_ target: Target) throws {
        try removeIf(target) { _ in true }
    }

    private func expand(_ target: Target) throws {
        try lock.withLock {
            let stack = try resolve(target)
            guard stack.notification.isCollapsedStack else {
                throw DemoNotificationsError.unknownAction(
                    name: "Expand", available: stack.notification.actions.map(\.name))
            }
            guard let position = entries.firstIndex(where: { $0.id == stack.id }) else { return }
            let members = stack.notification.members.map { member -> Entry in
                var member = member
                member.leavesAfter = stack.notification.leavesAfter
                defer { nextID += 1 }
                return Entry(id: nextID, notification: member)
            }
            entries.replaceSubrange(position...position, with: members)
        }
    }

    private func press(_ target: Target) throws {
        try removeIf(target) { notification in
            guard !notification.isCollapsedStack else {
                throw DemoNotificationsError.unknownAction(
                    name: "Activate", available: notification.actions.map(\.name))
            }
            return notification.activateCloses
        }
    }

    private func perform(action displayName: String, _ target: Target) throws {
        try removeIf(target) { notification in
            guard let action = notification.actions.first(where: { $0.name == displayName })
            else {
                throw DemoNotificationsError.unknownAction(
                    name: displayName, available: notification.actions.map(\.name))
            }
            return action.closes
        }
    }

    private func removeIf(_ target: Target, _ closes: (DemoNotification) throws -> Bool) throws {
        let removal = try lock.withLock { () -> (id: Int, takes: TimeInterval)? in
            let entry = try resolve(target)
            return try closes(entry.notification)
                ? (entry.id, entry.notification.takes ?? 0) : nil
        }
        guard let removal else { return }
        if removal.takes > 0 { Thread.sleep(forTimeInterval: removal.takes) }
        lock.withLock { entries.removeAll { $0.id == removal.id } }
    }

    private func resolve(_ target: Target) throws -> Entry {
        let presented = presentedEntries()
        switch target {
        case .index(let index):
            guard presented.indices.contains(index) else {
                throw DemoNotificationsError.indexOutOfRange(
                    requested: index, count: presented.count)
            }
            return presented[index]
        case .id(let id):
            guard let entry = presented.first(where: { $0.id == id }) else {
                throw DemoNotificationsError.notPresented(id: id)
            }
            return entry
        }
    }

    private func presentedEntries() -> [Entry] {
        let elapsed = now().timeIntervalSince(start)
        return entries.filter { entry in
            let arrived = elapsed >= (entry.notification.arrivesAfter ?? 0)
            let left = entry.notification.leavesAfter.map { elapsed >= $0 } ?? false
            return arrived && !left
        }
    }
}
