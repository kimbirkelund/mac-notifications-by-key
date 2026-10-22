import NotificationAX

public enum DemoNotificationCenterAccess {
    public static func make() -> NotificationCenterAccess {
        DefaultNotificationCenterAX(executableNamed: "demo-nc", panelAlwaysOpen: true)
    }
}
