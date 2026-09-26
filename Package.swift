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
        // Interactive mode: the overlay session (AppKit), kept out of the adapter and the CLI.
        .target(name: "InteractiveMode", dependencies: ["NotificationAX", "NotificationCore"]),
        .executableTarget(
            name: "nbk", dependencies: ["NotificationCore", "NotificationAX", "InteractiveMode"]),
        .executableTarget(name: "windowlist"),
        // Unit tier.
        .testTarget(name: "NotificationCoreTests", dependencies: ["NotificationCore"]),
        // Unit tier for the AX module's seam/factory logic (no Accessibility at runtime).
        .testTarget(
            name: "NotificationAXUnitTests",
            dependencies: ["NotificationAX", "NotificationCore"]),
        .testTarget(
            name: "InteractiveModeTests",
            dependencies: ["InteractiveMode", "NotificationAX", "NotificationCore"]),
        // AX-integration tier (gated on Accessibility trust at runtime).
        .testTarget(
            name: "NotificationAXIntegrationTests",
            dependencies: ["NotificationAX", "NotificationCore"]),
    ]
)
