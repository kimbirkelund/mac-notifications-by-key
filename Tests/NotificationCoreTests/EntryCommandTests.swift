import Testing

@testable import NotificationCore

@Suite("EntryCommand")
struct EntryCommandTests {
    private let scriptEditor = ["Activate", "Dismiss", "Show Details", "Show", "Close"]

    @Test("Space and a literal space resolve to activate", arguments: ["Space", " "])
    func activate(key: String) {
        #expect(EntryCommand.resolve(key: key, entries: scriptEditor) == .activate)
    }

    @Test func dismiss() {
        #expect(EntryCommand.resolve(key: "d", entries: scriptEditor) == .dismiss)
    }

    @Test func nameLettersResolveToActions() {
        #expect(EntryCommand.resolve(key: "c", entries: scriptEditor) == .action("Close"))
        #expect(EntryCommand.resolve(key: "h", entries: scriptEditor) == .action("Show"))
        #expect(EntryCommand.resolve(key: "s", entries: scriptEditor) == .action("Show Details"))
    }

    @Test func digitFallbackResolves() {
        let entries = ["Activate", "Dismiss", "Dd", "Ddd"]
        #expect(EntryCommand.resolve(key: "1", entries: entries) == .action("Dd"))
        #expect(EntryCommand.resolve(key: "2", entries: entries) == .action("Ddd"))
    }

    @Test("unassigned or upper-case keys resolve to nil", arguments: ["x", "D", "C", ""])
    func unknown(key: String) {
        #expect(EntryCommand.resolve(key: key, entries: scriptEditor) == nil)
    }

    @Test func emptyEntriesResolveToNil() {
        #expect(EntryCommand.resolve(key: " ", entries: []) == nil)
        #expect(EntryCommand.resolve(key: "d", entries: []) == nil)
    }

    @Test func entryWithNoAssignableKeyIsUnreachable() {
        let overflowing = (1...10).map { "D" + String(repeating: "d", count: $0) }
        let entries = ["Activate", "Dismiss"] + overflowing
        let keys = ActivatorAssignment.keys(for: entries)
        #expect(keys.last == "")
        #expect(EntryCommand.resolve(key: "", entries: entries) == nil)
        #expect(EntryCommand.resolve(key: "9", entries: entries) == .action(entries[10]))
        let reachable = (1...9).compactMap {
            EntryCommand.resolve(key: String($0), entries: entries)
        }
        #expect(!reachable.contains(.action(entries[11])))
    }
}
