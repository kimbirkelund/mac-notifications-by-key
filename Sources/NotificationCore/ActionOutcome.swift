public enum ActionOutcome {
    private static let genericFailure: Int32 = -25200

    public static func dependsOnApp(action: String) -> Bool {
        action == "Reply"
    }

    public static func isPerformed(action: String, app: String?, axError: Int32) -> Bool {
        axError == 0
            || (dependsOnApp(action: action) && app == "Slack" && axError == genericFailure)
    }
}
