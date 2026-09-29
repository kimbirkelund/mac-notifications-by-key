import Testing

@testable import NotificationCore

@Suite struct ActivatorAssignmentTests {
    @Test func activateIsSpaceAndDismissIsD() {
        #expect(ActivatorAssignment.keys(for: ["Activate", "Dismiss"]) == ["Space", "d"])
    }

    @Test func actionsTakeFirstFreeLetterOfTheirName() {
        let keys = ActivatorAssignment.keys(for: [
            "Activate", "Dismiss", "Show Details", "Show", "Close",
        ])
        #expect(keys == ["Space", "d", "s", "h", "c"])
    }

    @Test func reservedJAndKAreSkipped() {
        let keys = ActivatorAssignment.keys(for: ["Activate", "Dismiss", "Jk", "Kj"])
        #expect(keys == ["Space", "d", "1", "2"])
    }

    @Test func reservedLetterIsSkippedForNextLetterOfName() {
        let keys = ActivatorAssignment.keys(for: ["Activate", "Dismiss", "Jump"])
        #expect(keys == ["Space", "d", "u"])
    }

    @Test func dIsNotGivenToActions() {
        let keys = ActivatorAssignment.keys(for: ["Activate", "Dismiss", "Delete"])
        #expect(keys == ["Space", "d", "e"])
    }

    @Test func inputIsCaseInsensitiveAndOutputIsLowerCase() {
        let keys = ActivatorAssignment.keys(for: ["Activate", "Dismiss", "REPLY", "reply"])
        #expect(keys == ["Space", "d", "r", "e"])
    }

    @Test func digitsUsedWhenNoLetterIsFree() {
        let keys = ActivatorAssignment.keys(for: ["Activate", "Dismiss", "Reply", "Rep", "Re"])
        #expect(keys == ["Space", "d", "r", "e", "1"])
    }

    @Test func nonLettersAreSkipped() {
        let keys = ActivatorAssignment.keys(for: ["Activate", "Dismiss", "1st Try", "42"])
        #expect(keys == ["Space", "d", "s", "1"])
    }

    @Test func digitsStartAtOneAndAreUnique() {
        let keys = ActivatorAssignment.keys(for: ["Activate", "Dismiss", "!", "?", "-"])
        #expect(keys == ["Space", "d", "1", "2", "3"])
    }

    @Test func nonAsciiLettersAreValidActivators() {
        let keys = ActivatorAssignment.keys(for: ["Activate", "Dismiss", "Écrire"])
        #expect(keys == ["Space", "d", "é"])
    }

    @Test func actionNamedDismissOrActivateGetsOrdinaryKeys() {
        let keys = ActivatorAssignment.keys(for: ["Activate", "Dismiss", "Dismiss", "Activate"])
        #expect(keys == ["Space", "d", "i", "a"])
    }
}
