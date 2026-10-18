public enum AppFilter: Equatable, Sendable {
    case any
    case app(String?)

    public func matches(_ item: NotificationItem) -> Bool {
        switch self {
        case .any: return true
        case .app(let name): return item.app == name
        }
    }
}

public enum ClearStep: Equatable, Sendable {
    case close(Int)
    case clearAll(Int)

    public static func next(in items: [NotificationItem], app: AppFilter) -> ClearStep? {
        guard let offset = items.firstIndex(where: app.matches) else { return nil }
        let actions = items[offset].actions
        if actions.contains("Clear All") && !actions.contains("Close") {
            return .clearAll(offset)
        }
        return .close(offset)
    }
}
