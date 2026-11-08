import Testing

@testable import NotificationCore

@Suite struct DismissActionTests {
    @Test func plainNotificationUsesClose() {
        #expect(DismissAction.name(for: ["Close", "Reply"]) == "Close")
    }

    @Test func explicitDismissIsPreferredOverClose() {
        #expect(DismissAction.name(for: ["Close", "Dismiss", "Reply"]) == "Dismiss")
    }

    @Test func collapsedStackUsesClearAll() {
        #expect(DismissAction.name(for: ["Clear All"]) == "Clear All")
    }

    @Test func collapsedStackWithDismissStillUsesClearAll() {
        #expect(DismissAction.name(for: ["Clear All", "Dismiss"]) == "Clear All")
    }

    @Test func dismissMatchIsCaseSensitive() {
        #expect(DismissAction.name(for: ["Close", "dismiss"]) == "Close")
    }
}
