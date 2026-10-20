import Testing

@testable import NotificationCore

@Suite("GlobalCommand")
struct GlobalCommandTests {
    @Test func upperCaseXClearsAll() {
        #expect(GlobalCommand.resolve(key: "X") == .clearAll)
    }

    @Test func upperCaseDDismissesAllForApp() {
        #expect(GlobalCommand.resolve(key: "D") == .dismissAllForApp)
    }

    @Test("other keys resolve to nil", arguments: ["x", "C", "c", "d", "Space", "", "XX"])
    func unknown(key: String) {
        #expect(GlobalCommand.resolve(key: key) == nil)
    }
}
