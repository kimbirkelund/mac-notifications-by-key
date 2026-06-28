import Foundation
import NotificationCore
import Testing

@testable import NotificationAX

/// AX-integration tier (docs/testing.md). Requires a real Notification Center and
/// Accessibility trust for the test host; delivers real notifications via
/// `osascript`. Gated: skipped (not failed) when trust is absent.
///
/// `.serialized`: these tests act on the single, process-wide Notification Center,
/// so they must not run concurrently — parallel delivery races and same-app banner
/// coalescing would otherwise make them flaky. Each test also clears the Center
/// first for a clean slate.
@Suite(.serialized) struct NotificationAXIntegrationTests {
    static var available: Bool {
        NotificationAX.isTrusted && NotificationAX.notificationCenterPID() != nil
    }

    @discardableResult
    func deliver(title: String, body: String = "integration body") -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \"\(body)\" with title \"\(title)\""]
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Dismiss everything currently presented, so a test starts from empty.
    func clearAll() {
        for _ in 0..<10 {
            let items = (try? NotificationAX.read(wait: 0)) ?? []
            if items.isEmpty { return }
            try? NotificationAX.dismiss(index: 0)
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    @Test(.enabled(if: NotificationAXIntegrationTests.available))
    func readsDeliveredNotification() throws {
        clearAll()
        let title = "AXIntegrationProbe"
        #expect(deliver(title: title))
        let items = try NotificationAX.read(wait: 6)
        #expect(items.contains { $0.title == title })
        clearAll()
    }

    @Test(.enabled(if: NotificationAXIntegrationTests.available))
    func dismissRemovesNewest() throws {
        clearAll()
        let title = "AXDismissProbe"
        #expect(deliver(title: title))
        let before = try NotificationAX.read(wait: 6)
        guard let idx = before.firstIndex(where: { $0.title == title }) else {
            Issue.record("delivered notification did not appear")
            return
        }
        try NotificationAX.dismiss(index: idx)
        Thread.sleep(forTimeInterval: 0.8)
        let after = try NotificationAX.read(wait: 0)
        #expect(!after.contains { $0.title == title })
    }
}
