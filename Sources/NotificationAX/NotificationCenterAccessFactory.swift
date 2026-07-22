/// Selects the `NotificationCenterAccess` implementation. A single implementation
/// exists today; when a second layout implementation is added, branch here on
/// `ProcessInfo.processInfo.operatingSystemVersion` (docs/constraints.md C-6, C-3).
public enum NotificationCenterAccessFactory {
    public static func make() -> NotificationCenterAccess {
        DefaultNotificationCenterAX()
    }
}
