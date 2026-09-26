public enum InteractiveError: Error, Equatable, Sendable {
    case noScreen

    public var message: String {
        switch self {
        case .noScreen:
            return "No display is available; interactive mode needs a screen to draw its overlay."
        }
    }

    public var exitCode: Int32 {
        switch self {
        case .noScreen: return 1
        }
    }
}
