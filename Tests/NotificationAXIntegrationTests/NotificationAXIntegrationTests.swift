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
    /// Bounds `clearAll`'s dismiss loop so a Center that won't drain can't hang the suite.
    static let maxClearAttempts = 10
    /// Let a dismissal settle before the next `clearAll` read (Close is async).
    static let clearSettleDelay: TimeInterval = 0.3
    /// Poll past the ~1s banner render delay (docs/constraints.md C-3) when reading a delivery.
    static let deliveryReadTimeout: TimeInterval = 6

    let nc = NotificationCenterAccessFactory.make()

    static var available: Bool {
        let nc = NotificationCenterAccessFactory.make()
        return nc.isTrusted && nc.notificationCenterPID() != nil
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
        for _ in 0..<Self.maxClearAttempts {
            let items = (try? nc.read(wait: 0)) ?? []
            if items.isEmpty { return }
            try? nc.dismiss(index: 0)
            Thread.sleep(forTimeInterval: Self.clearSettleDelay)
        }
    }

    @Test(.enabled(if: NotificationAXIntegrationTests.available))
    func readsDeliveredNotification() throws {
        clearAll()
        let title = "AXIntegrationProbe"
        #expect(deliver(title: title))
        let items = try nc.read(wait: 6)
        #expect(items.contains { $0.title == title })
        clearAll()
    }

    @Test(.enabled(if: NotificationAXIntegrationTests.available))
    func dismissRemovesNewest() throws {
        clearAll()
        let title = "AXDismissProbe"
        #expect(deliver(title: title))
        let before = try nc.read(wait: Self.deliveryReadTimeout)
        guard let idx = before.firstIndex(where: { $0.title == title }) else {
            Issue.record("delivered notification did not appear")
            return
        }
        // dismiss polls (bounded) until the element leaves the tree, so it is gone on return.
        try nc.dismiss(index: idx)
        let after = try nc.read(wait: 0)
        #expect(!after.contains { $0.title == title })
    }
}
