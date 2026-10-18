import Testing

@testable import NotificationCore

@Suite struct ClearStepTests {
    private func item(_ index: Int, app: String? = nil, actions: [String] = ["Close"])
        -> NotificationItem
    {
        NotificationItem(index: index, app: app, actions: actions)
    }

    @Test func emptyListHasNoStep() {
        #expect(ClearStep.next(in: [], app: .any) == nil)
    }

    @Test func firstItemWithCloseIsClosed() {
        let items = [item(0), item(1)]
        #expect(ClearStep.next(in: items, app: .any) == .close(0))
    }

    @Test func firstItemWithClearAllAndNoCloseIsClearedAll() {
        let items = [item(0, actions: ["Clear All"]), item(1)]
        #expect(ClearStep.next(in: items, app: .any) == .clearAll(0))
    }

    @Test func itemWithBothCloseAndClearAllIsClosed() {
        let items = [item(0, actions: ["Close", "Clear All"])]
        #expect(ClearStep.next(in: items, app: .any) == .close(0))
    }

    @Test func itemWithNeitherCloseNorClearAllFallsBackToClose() {
        #expect(ClearStep.next(in: [item(0, actions: [])], app: .any) == .close(0))
    }

    @Test func appFilterSkipsNonMatchingAndReturnsFirstMatch() {
        let items = [item(0, app: "Mail"), item(1, app: "Slack"), item(2, app: "Slack")]
        #expect(ClearStep.next(in: items, app: .app("Slack")) == .close(1))
    }

    @Test func nilAppMatchesOnlyNil() {
        let items = [item(0, app: "Mail"), item(1, app: nil)]
        #expect(ClearStep.next(in: items, app: .app(nil)) == .close(1))
    }

    @Test func namedAppDoesNotMatchNil() {
        #expect(ClearStep.next(in: [item(0, app: nil)], app: .app("Mail")) == nil)
    }

    @Test func noMatchHasNoStep() {
        #expect(ClearStep.next(in: [item(0, app: "Mail")], app: .app("Slack")) == nil)
    }
}
