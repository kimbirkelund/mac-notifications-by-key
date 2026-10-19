import Testing

@testable import NotificationCore

@Suite("GlobalCommand")
struct GlobalCommandTests {
    @Test func upperCaseXClearsAll() {
        #expect(GlobalCommand.resolve(key: "X") == .clearAll)
    }

    @Test func upperCaseCClearsAllForApp() {
        #expect(GlobalCommand.resolve(key: "C") == .clearAllForApp)
    }

    @Test("other keys resolve to nil", arguments: ["x", "c", "d", "Space", "", "XX"])
    func unknown(key: String) {
        #expect(GlobalCommand.resolve(key: key) == nil)
    }
}
