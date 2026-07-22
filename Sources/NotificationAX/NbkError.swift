/// Errors surfaced by the AX adapter, mapped to CLI exit codes in `nbk`.
public enum NbkError: Error, Sendable {
    case notTrusted
    case noNotificationCenter
    case indexOutOfRange(requested: Int, count: Int)
    case unknownAction(name: String, available: [String])
    case actionFailed(name: String)

    public var message: String {
        switch self {
        case .notTrusted:
            return "Accessibility permission not granted. Grant it in System Settings → "
                + "Privacy & Security → Accessibility for the process that runs nbk (e.g. your "
                + "terminal or skhd), then retry."
        case .noNotificationCenter:
            return
                "Could not find the Notification Center process (com.apple.notificationcenterui)."
        case .indexOutOfRange(let requested, let count):
            return "No notification at index \(requested) (currently \(count) presented)."
        case .unknownAction(let name, let available):
            return "Notification does not expose action \"\(name)\". Available: \(available)."
        case .actionFailed(let name):
            return "Performing action \"\(name)\" failed."
        }
    }

    /// 1 = generic, 2 = bad selection/argument, 3 = missing permission.
    public var exitCode: Int32 {
        switch self {
        case .notTrusted: return 3
        case .indexOutOfRange, .unknownAction: return 2
        default: return 1
        }
    }
}
