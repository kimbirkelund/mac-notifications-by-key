public enum EntryCommand: Equatable, Sendable {
    case activate
    case dismiss
    case action(String)

    public static func resolve(key: String, entries: [String]) -> EntryCommand? {
        let normalized = key == " " ? "Space" : key
        guard !normalized.isEmpty,
            let index = ActivatorAssignment.keys(for: entries).firstIndex(of: normalized)
        else { return nil }
        switch index {
        case 0: return .activate
        case 1: return .dismiss
        default: return .action(entries[index])
        }
    }
}
