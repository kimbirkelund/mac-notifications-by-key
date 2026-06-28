// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac-notifications-by-key",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic — no Accessibility, fully unit-testable.
        .target(name: "NotificationCore"),
        // Accessibility adapter — reads/acts on the live Notification Center tree.
        .target(name: "NotificationAX", dependencies: ["NotificationCore"]),
        // The CLI executable.
        .executableTarget(name: "nbk", dependencies: ["NotificationCore", "NotificationAX"]),
        // Unit tier.
        .testTarget(name: "NotificationCoreTests", dependencies: ["NotificationCore"]),
        // AX-integration tier (gated on Accessibility trust at runtime).
        .testTarget(
            name: "NotificationAXIntegrationTests",
            dependencies: ["NotificationAX", "NotificationCore"]),
    ]
)
