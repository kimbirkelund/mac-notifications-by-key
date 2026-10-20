public enum GlobalCommand: Equatable, Sendable {
    case clearAll
    case dismissAllForApp

    public static func resolve(key: String) -> GlobalCommand? {
        switch key {
        case "X": return .clearAll
        case "D": return .dismissAllForApp
        default: return nil
        }
    }
}
