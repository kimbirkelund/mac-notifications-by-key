import Testing

@testable import NotificationCore

@Suite struct CollapsedStackTests {
    @Test func clearAllWithoutCloseIsCollapsedStack() {
        #expect(CollapsedStack.matches(actions: ["Clear All", "Show"]))
    }

    @Test func clearAllWithCloseIsNotCollapsedStack() {
        #expect(!CollapsedStack.matches(actions: ["Clear All", "Close"]))
    }

    @Test func noActionsIsNotCollapsedStack() {
        #expect(!CollapsedStack.matches(actions: []))
    }
}
