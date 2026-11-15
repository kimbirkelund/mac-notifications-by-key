import Foundation

public final class PendingEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DemoEvent] = []

    public init() {}

    public func append(_ event: DemoEvent) { lock.withLock { events.append(event) } }

    public func take(through seq: Int) -> [DemoEvent] {
        lock.withLock {
            let count = events.prefix { $0.seq <= seq }.count
            let taken = Array(events.prefix(count))
            events.removeFirst(count)
            return taken
        }
    }
}
