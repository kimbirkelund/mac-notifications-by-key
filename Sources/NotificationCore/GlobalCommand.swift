public enum GlobalCommand: Equatable, Sendable {
    case clearAll
    case clearAllForApp

    public static func resolve(key: String) -> GlobalCommand? {
        switch key {
        case "X": return .clearAll
        case "C": return .clearAllForApp
        default: return nil
        }
    }
}
