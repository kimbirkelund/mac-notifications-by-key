import Foundation
import NotificationCore
import Testing

@testable import NotificationAX

/// AX-integration tier: reads a running `demo-nc` through the real adapter configured
/// for it. Gated on Accessibility trust and a built `demo-nc` binary.
@Suite(.serialized) struct DemoNotificationCenterAXTests {
    private final class BundleAnchor {}

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static var demoBinary: URL? {
        if let override = ProcessInfo.processInfo.environment["DEMO_NC_BIN"] {
            return URL(fileURLWithPath: override)
        }
        let sibling = Bundle(for: BundleAnchor.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("demo-nc")
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }

    static var available: Bool {
        NotificationCenterAccessFactory.make().isTrusted && demoBinary != nil
    }

    private func launchDemo(fixture: String) throws -> Process {
        let process = Process()
        process.executableURL = try #require(Self.demoBinary)
        process.arguments = [
            "--open",
            Self.repoRoot.appendingPathComponent("acceptance/fixtures/\(fixture)").path,
        ]
        try process.run()
        return process
    }

    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func readsTheStackFixtureThroughTheRealAdapter() throws {
        let demo = try launchDemo(fixture: "stack.json")
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(
            executableNamed: "demo-nc", panelAlwaysOpen: true)

        let items = try ax.read(wait: 6)
        #expect(items.map(\.title) == ["Inbox", "Meeting"])
        #expect(items.map(\.app) == ["Mail", "Calendar"])
        #expect(items[0].isCollapsedStack)
        #expect(items[0].actions.contains("Clear All"))
        #expect(!items[0].actions.contains("Close"))
        #expect(!items[1].isCollapsedStack)
        #expect(items[1].actions.contains("Snooze"))
        #expect(items[1].actions.contains("Close"))

        let presented = try ax.readPresented()
        #expect(presented[0].extentBelow > 0)
    }
}
