import Foundation
import NotificationCore

public enum DemoNotificationsError: Error, Equatable, Sendable {
    case indexOutOfRange(requested: Int, count: Int)
    case unknownAction(name: String, available: [String])
    case notPresented(id: Int)
}

public struct DemoRenderSnapshot: Equatable, Sendable {
    public var presented: [DemoPresentedNotification]
    public var listOpen: Bool
    public var seq: Int
}

public struct DemoPresentedNotification: Equatable, Sendable {
    public var id: Int
    public var item: NotificationItem
    public var hiddenMembers: Int
    public var showsField: Bool
    public var failingActions: Set<String>

    public init(
        id: Int, item: NotificationItem, hiddenMembers: Int, showsField: Bool = false,
        failingActions: Set<String> = []
    ) {
        self.id = id
        self.item = item
        self.hiddenMembers = hiddenMembers
        self.showsField = showsField
        self.failingActions = failingActions
    }
}

public final class DemoNotificationsModel: @unchecked Sendable {
    private struct Entry {
        var id: Int
        var notification: DemoNotification
        var showsField = false
    }

    private enum Target {
        case index(Int)
        case id(Int)
    }

    private enum Step {
        case done(applied: Bool)
        case remove(id: Int, takes: TimeInterval)
    }

    private struct Report {
        var kind: DemoActionKind
        var id: Int?
        var name: String?
        var text: String?
    }

    private let lock = NSLock()
    private let eventLock = NSLock()
    private var entries: [Entry]
    private var listOpen: Bool
    private var sequence = 0
    private var knownIDs: Set<Int>
    private var outbox: [DemoEvent] = []
    private var eventObserver: (@Sendable (DemoEvent) -> Void)?
    private var nextID: Int
    private var signalled = false
    private let now: () -> Date
    private let start: Date

    public var observer: (@Sendable (DemoEvent) -> Void)? {
        get { eventLock.withLock { eventObserver } }
        set { eventLock.withLock { eventObserver = newValue } }
    }

    public init(
        notifications: [DemoNotification], isListOpen: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.entries = notifications.enumerated().map {
            Entry(id: $0.offset, notification: $0.element)
        }
        self.nextID = notifications.count
        self.listOpen = isListOpen
        self.now = now
        self.start = now()
        self.knownIDs = []
        self.knownIDs = Set(presentedEntries().map(\.id))
    }

    public var isListOpen: Bool { lock.withLock { listOpen } }

    public func state() -> DemoState { lock.withLock { snapshot() } }

    public func renderSnapshot() -> DemoRenderSnapshot {
        lock.withLock {
            DemoRenderSnapshot(presented: presentedList(), listOpen: listOpen, seq: sequence)
        }
    }

    public func ready() {
        lock.withLock { enqueue(.ready) }
        flush()
    }

    public func setListOpen(_ open: Bool) {
        lock.withLock {
            guard listOpen != open else { return }
            listOpen = open
            enqueue(open ? .listOpened : .listClosed)
        }
        flush()
    }

    public func signal() {
        lock.withLock {
            signalled = true
            advanceLocked()
        }
        flush()
    }

    public func advance() {
        lock.withLock { advanceLocked() }
        flush()
    }

    public func items() -> [NotificationItem] {
        lock.withLock {
            presentedEntries().enumerated().map { index, entry in
                entry.notification.item(index: index)
            }
        }
    }

    public func presented() -> [DemoPresentedNotification] {
        lock.withLock { presentedList() }
    }

    public func dismiss(index: Int) throws {
        try act(Report(kind: .close), .index(index)) { try removeStep(.index(index)) { _ in true } }
    }

    public func dismiss(id: Int) throws {
        try act(Report(kind: .close), .id(id)) { try removeStep(.id(id)) { _ in true } }
    }

    public func clearAll(id: Int) throws {
        try act(Report(kind: .clearAll), .id(id)) { try removeStep(.id(id)) { _ in true } }
    }

    public func clearAll() {
        try? act(Report(kind: .clearAll), nil) {
            let ids = Set(presentedEntries().map(\.id))
            entries.removeAll { ids.contains($0.id) }
            return .done(applied: true)
        }
    }

    public func clearAll(forApp index: Int) throws {
        try act(Report(kind: .clearAll), .index(index)) {
            let presented = presentedEntries()
            guard presented.indices.contains(index) else {
                throw DemoNotificationsError.indexOutOfRange(
                    requested: index, count: presented.count)
            }
            let app = presented[index].notification.app
            let ids = Set(presented.filter { $0.notification.app == app }.map(\.id))
            entries.removeAll { ids.contains($0.id) }
            return .done(applied: true)
        }
    }

    public func expand(index: Int) throws {
        try act(Report(kind: .expand), .index(index)) { try expandStep(.index(index)) }
    }

    public func expand(id: Int) throws {
        try act(Report(kind: .expand), .id(id)) { try expandStep(.id(id)) }
    }

    public func press(index: Int) throws {
        try act(Report(kind: .press), .index(index)) { try pressStep(.index(index)) }
    }

    public func press(id: Int) throws {
        try act(Report(kind: .press), .id(id)) { try pressStep(.id(id)) }
    }

    public func perform(action displayName: String, index: Int) throws {
        try act(Report(kind: .named, name: displayName), .index(index)) {
            try performStep(displayName, .index(index))
        }
    }

    public func perform(action displayName: String, id: Int) throws {
        try act(Report(kind: .named, name: displayName), .id(id)) {
            try performStep(displayName, .id(id))
        }
    }

    public func submitField(id: Int, text: String) throws {
        try act(Report(kind: .submitField, text: text), .id(id)) {
            try removeStep(.id(id)) { _ in true }
        }
    }

    public func cancelField(id: Int) throws {
        try lock.withLock {
            let entry = try resolve(.id(id))
            guard let position = entries.firstIndex(where: { $0.id == entry.id }) else { return }
            entries[position].showsField = false
        }
    }

    private func act(_ report: Report, _ target: Target?, _ body: () throws -> Step) throws {
        var report = report
        var failure: Error?
        let pendingRemoval = lock.withLock { () -> (id: Int, takes: TimeInterval)? in
            advanceLocked()
            report.id = target.flatMap(targetID)
            let before = Set(entries.map(\.id))
            do {
                switch try body() {
                case .done(let applied):
                    syncKnownIDs(from: before)
                    enqueueAction(report, applied ? .applied : .kept)
                case .remove(let id, let takes):
                    if takes > 0 { return (id, takes) }
                    entries.removeAll { $0.id == id }
                    syncKnownIDs(from: before)
                    enqueueAction(report, .applied)
                }
            } catch {
                failure = error
                enqueueAction(report, .failed, error: error)
            }
            return nil
        }
        flush()
        if let failure { throw failure }
        guard let pendingRemoval else { return }
        Thread.sleep(forTimeInterval: pendingRemoval.takes)
        lock.withLock {
            advanceLocked()
            let before = Set(entries.map(\.id))
            entries.removeAll { $0.id == pendingRemoval.id }
            syncKnownIDs(from: before)
            enqueueAction(report, .applied)
        }
        flush()
    }

    private func targetID(_ target: Target) -> Int? {
        switch target {
        case .index: return try? resolve(target).id
        case .id(let id): return id
        }
    }

    private func syncKnownIDs(from before: Set<Int>) {
        let after = Set(entries.map(\.id))
        knownIDs.subtract(before.subtracting(after))
        knownIDs.formUnion(after.subtracting(before))
    }

    private func advanceLocked() {
        let current = presentedEntries().map(\.id)
        let arrived = current.filter { !knownIDs.contains($0) }
        let departed = knownIDs.subtracting(current).sorted()
        knownIDs = Set(current)
        for id in arrived { enqueue(.arrived, id: id) }
        for id in departed { enqueue(.departed, id: id) }
    }

    private func enqueueAction(_ report: Report, _ outcome: DemoOutcome, error: Error? = nil) {
        enqueue(
            .action, id: report.id, kind: report.kind, action: report.name, outcome: outcome,
            error: error.map { String(describing: $0) }, text: report.text)
    }

    private func enqueue(
        _ event: DemoEventKind, id: Int? = nil, kind: DemoActionKind? = nil,
        action: String? = nil, outcome: DemoOutcome? = nil, error: String? = nil,
        text: String? = nil
    ) {
        sequence += 1
        outbox.append(
            DemoEvent(
                seq: sequence, event: event, state: snapshot(), id: id, kind: kind,
                action: action, outcome: outcome, error: error, text: text))
    }

    private func flush() {
        eventLock.withLock {
            while true {
                let next = lock.withLock { outbox.isEmpty ? nil : outbox.removeFirst() }
                guard let next else { return }
                eventObserver?(next)
            }
        }
    }

    private func removeStep(_ target: Target, _ closes: (Entry) throws -> Bool) throws -> Step {
        let entry = try resolve(target)
        return try closes(entry)
            ? .remove(id: entry.id, takes: entry.notification.takes ?? 0) : .done(applied: false)
    }

    private func expandStep(_ target: Target) throws -> Step {
        let stack = try resolve(target)
        guard stack.notification.isCollapsedStack else {
            throw DemoNotificationsError.unknownAction(
                name: "Expand", available: stack.notification.actions.map(\.name))
        }
        guard let position = entries.firstIndex(where: { $0.id == stack.id }) else {
            return .done(applied: true)
        }
        let members = stack.notification.members.map { member -> Entry in
            var member = member
            member.leavesAfter = stack.notification.leavesAfter
            member.leavesOn = stack.notification.leavesOn
            defer { nextID += 1 }
            return Entry(id: nextID, notification: member)
        }
        entries.replaceSubrange(position...position, with: members)
        return .done(applied: true)
    }

    private func pressStep(_ target: Target) throws -> Step {
        try removeStep(target) { entry in
            let notification = entry.notification
            guard !notification.isCollapsedStack else {
                throw DemoNotificationsError.unknownAction(
                    name: "Activate", available: notification.actions.map(\.name))
            }
            return notification.activateCloses
        }
    }

    private func performStep(_ displayName: String, _ target: Target) throws -> Step {
        try removeStep(target) { entry in
            let notification = entry.notification
            guard let action = notification.actions.first(where: { $0.name == displayName })
            else {
                throw DemoNotificationsError.unknownAction(
                    name: displayName, available: notification.actions.map(\.name))
            }
            if action.field {
                if let position = entries.firstIndex(where: { $0.id == entry.id }) {
                    entries[position].showsField = true
                }
                return false
            }
            return action.closes
        }
    }

    private func presentedList() -> [DemoPresentedNotification] {
        presentedEntries().enumerated().map { index, entry in
            DemoPresentedNotification(
                id: entry.id, item: entry.notification.item(index: index),
                hiddenMembers: entry.notification.members.count,
                showsField: entry.showsField,
                failingActions: Set(entry.notification.actions.filter(\.fails).map(\.name)))
        }
    }

    private func snapshot() -> DemoState {
        DemoState(
            notifications: presentedEntries().map { entry in
                let n = entry.notification
                return DemoNotificationState(
                    id: entry.id, app: n.app, title: n.title, subtitle: n.subtitle, body: n.body,
                    actions: n.actions.map(\.name), collapsedStack: n.isCollapsedStack,
                    hiddenMembers: n.members.count, replyField: entry.showsField)
            },
            listOpen: listOpen)
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
            let n = entry.notification
            let arrived =
                elapsed >= (n.arrivesAfter ?? 0) && (n.arrivesOn != .signal || signalled)
            let left =
                (n.leavesAfter.map { elapsed >= $0 } ?? false)
                || (n.leavesOn == .signal && signalled)
            return arrived && !left
        }
    }
}
