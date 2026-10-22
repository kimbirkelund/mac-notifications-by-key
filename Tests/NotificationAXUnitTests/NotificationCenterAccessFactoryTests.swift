import Testing

@testable import NotificationAX

/// Unit tier (docs/testing.md): the factory selects an implementation with no
/// Accessibility calls, so this runs untrusted in CI.
@Suite struct NotificationCenterAccessFactoryTests {
    /// C-5: a single implementation is provided today; the factory is the sole
    /// selection point. Becomes the seam for version-based selection later.
    @Test func makeReturnsTheDefaultImplementation() {
        #expect(NotificationCenterAccessFactory.make() is DefaultNotificationCenterAX)
    }
}

@Suite struct DemoConfigurationTests {
    private let ax = DefaultNotificationCenterAX(
        executableNamed: "no-such-demo-process", panelAlwaysOpen: true)

    @Test func findsNoProcessWhenNoneMatchesThePath() {
        #expect(ax.notificationCenterPID() == nil)
    }

    @Test func theDemoPanelIsAlwaysOpenAndClosingIsANoOp() throws {
        #expect(ax.isPanelOpen)
        try ax.setPanelOpen(false)
        #expect(ax.isPanelOpen)
    }

    @Test func onlyTheFinalPathComponentMatchesTheExecutableName() {
        let match = DefaultNotificationCenterAX.executablePath
        #expect(match("/work/demo-nc/.build/debug/demo-nc", "demo-nc"))
        #expect(!match("/work/demo-nc/.build/debug/nbk", "demo-nc"))
        #expect(!match("/work/demo-nc/", "demo-nc"))
        #expect(!match("/work/not-demo-nc", "demo-nc"))
    }
}
