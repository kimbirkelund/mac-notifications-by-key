import Foundation
import Testing

@testable import NotificationCore

@Suite struct ActionNameTests {
    @Test func extractsDisplayNameFromAXAction() {
        #expect(
            ActionName.display(fromAXAction: "Name:Close\nTarget:0x0\nSelector:(null)") == "Close")
        #expect(
            ActionName.display(fromAXAction: "Name:Show Details\nTarget:0x0\nSelector:(null)")
                == "Show Details")
    }

    @Test func passesPlainActionsThrough() {
        #expect(ActionName.display(fromAXAction: "AXPress") == "AXPress")
    }

    @Test func mapsDisplayNameBackToRawAction() {
        let raws = ["AXPress", "Name:Close\nTarget:0x0\nSelector:(null)"]
        #expect(ActionName.axAction(named: "Close", in: raws) == raws[1])
        #expect(ActionName.axAction(named: "Nope", in: raws) == nil)
    }
}

@Suite struct SelectionTests {
    let items = [
        NotificationItem(index: 0, title: "a"),
        NotificationItem(index: 1, title: "b"),
    ]

    @Test func returnsItemInRange() {
        #expect(Selection.at(items, 1)?.title == "b")
    }

    @Test func returnsNilOutOfRange() {
        #expect(Selection.at(items, 2) == nil)
        #expect(Selection.at(items, -1) == nil)
    }
}

@Suite struct OutputTests {
    @Test func emptyListRendersAsEmptyJSONArray() throws {
        #expect(try Output.json([]) == "[]")
    }

    @Test func jsonRoundTrips() throws {
        let items = [
            NotificationItem(
                index: 0, app: "Messages", title: "T", subtitle: "S", body: "B",
                actions: ["Close", "Show"])
        ]
        let json = try Output.json(items)
        let decoded = try JSONDecoder().decode([NotificationItem].self, from: Data(json.utf8))
        #expect(decoded == items)
    }
}

@Suite struct WaitOptionTests {
    @Test func absentDefaultsToZero() throws {
        #expect(try WaitOption.parse(["list"]) == 0)
    }

    @Test func parsesIntegerSeconds() throws {
        #expect(try WaitOption.parse(["list", "--wait", "5"]) == 5)
    }

    @Test func parsesFractionalSeconds() throws {
        #expect(try WaitOption.parse(["list", "--wait", "2.5"]) == 2.5)
    }

    @Test func zeroIsAllowed() throws {
        #expect(try WaitOption.parse(["--wait", "0"]) == 0)
    }

    @Test func missingValueThrows() {
        #expect(throws: ArgumentError.missingValue(flag: "--wait")) {
            try WaitOption.parse(["list", "--wait"])
        }
    }

    @Test func nonNumericValueThrows() {
        #expect(throws: ArgumentError.invalidValue(flag: "--wait", value: "soon")) {
            try WaitOption.parse(["list", "--wait", "soon"])
        }
    }

    @Test func followingFlagIsNotAValue() {
        #expect(throws: ArgumentError.invalidValue(flag: "--wait", value: "--version")) {
            try WaitOption.parse(["list", "--wait", "--version"])
        }
    }

    @Test func negativeValueThrows() {
        #expect(throws: ArgumentError.negativeValue(flag: "--wait", value: "-1")) {
            try WaitOption.parse(["list", "--wait", "-1"])
        }
    }
}
