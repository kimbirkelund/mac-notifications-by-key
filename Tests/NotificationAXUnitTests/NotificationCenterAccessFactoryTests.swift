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
