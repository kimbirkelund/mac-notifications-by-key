import Foundation
import NotificationCore
import Testing

@testable import DemoNotifications

@Suite struct DemoFileTests {
    private func decode(_ json: String) throws -> DemoFile {
        try DemoFile.decode(from: Data(json.utf8))
    }

    @Test func bareStringActionCloses() throws {
        let file = try decode(#"{"notifications":[{"title":"t","actions":["Archive"]}]}"#)
        #expect(file.notifications[0].actions == [DemoAction(name: "Archive", closes: true)])
    }

    @Test func objectActionHonoursClosesFalse() throws {
        let file = try decode(
            #"{"notifications":[{"actions":[{"name":"Reply","closes":false}]}]}"#)
        #expect(file.notifications[0].actions == [DemoAction(name: "Reply", closes: false)])
    }

    @Test func objectActionWithoutClosesCloses() throws {
        let file = try decode(#"{"notifications":[{"actions":[{"name":"Reply"}]}]}"#)
        #expect(file.notifications[0].actions[0].closes)
    }

    @Test func activateClosesDefaultsToTrue() throws {
        let file = try decode(#"{"notifications":[{"title":"t"}]}"#)
        #expect(file.notifications[0].activateCloses)
    }

    @Test func activateClosesExplicitFalse() throws {
        let file = try decode(#"{"notifications":[{"activateCloses":false}]}"#)
        #expect(!file.notifications[0].activateCloses)
    }

    @Test func optionalFieldsAndActionsMayBeAbsentOrNull() throws {
        let file = try decode(
            #"{"notifications":[{"app":"Mail","title":"t","subtitle":null}]}"#)
        let n = file.notifications[0]
        #expect(n.app == "Mail")
        #expect(n.subtitle == nil)
        #expect(n.body == nil)
        #expect(n.actions.isEmpty)
    }

    @Test func membersDecodeAndFlagTheItemAsACollapsedStack() throws {
        let file = try decode(
            #"{"notifications":[{"title":"s","members":[{"title":"a"},{"title":"b"}]},{"title":"p"}]}"#
        )
        #expect(file.notifications[0].members.map(\.title) == ["a", "b"])
        #expect(file.notifications[0].item(index: 0).isCollapsedStack)
        #expect(!file.notifications[1].item(index: 1).isCollapsedStack)
        #expect(file.notifications[1].members.isEmpty)
    }

    @Test func nestedMembersAreRejected() {
        #expect(throws: DemoFileError.self) {
            try decode(
                #"{"notifications":[{"members":[{"title":"a","members":[{"title":"b"}]}]}]}"#)
        }
    }

    @Test func unknownKeysAreIgnored() throws {
        let file = try decode(
            #"{"x":1,"notifications":[{"title":"t","y":2,"actions":[{"name":"A","z":3}]}]}"#)
        #expect(file.notifications.count == 1)
        #expect(file.notifications[0].actions[0].name == "A")
    }

    @Test func invalidJSONThrowsDescriptiveError() {
        #expect(throws: DemoFileError.self) { try decode("{not json") }
        do {
            _ = try decode("{not json")
        } catch {
            #expect(!"\(error)".isEmpty)
            #expect((error as? DemoFileError)?.description.isEmpty == false)
        }
    }

    @Test func missingNotificationsKeyThrows() {
        #expect(throws: DemoFileError.self) { try decode(#"{"other":[]}"#) }
    }

    @Test func actionOfWrongShapeThrows() {
        #expect(throws: DemoFileError.self) {
            try decode(#"{"notifications":[{"actions":[42]}]}"#)
        }
    }

    @Test func missingFileThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/demo.json")
        #expect(throws: DemoFileError.self) { try DemoFile.load(from: url) }
    }

    @Test func itemMapsFieldsAndActionNames() throws {
        let file = try decode(
            #"{"notifications":[{"app":"Mail","title":"t","body":"b","actions":["A",{"name":"B","closes":false}]}]}"#
        )
        #expect(
            file.notifications[0].item(index: 3)
                == NotificationItem(
                    index: 3, app: "Mail", title: "t", subtitle: nil, body: "b",
                    actions: ["A", "B"]))
    }

    @Test func timingFieldsDecode() throws {
        let file = try decode(
            #"{"notifications":[{"title":"a","arrivesAfter":1.5,"leavesAfter":4},{"title":"b"}]}"#)
        #expect(file.notifications[0].arrivesAfter == 1.5)
        #expect(file.notifications[0].leavesAfter == 4)
        #expect(file.notifications[1].arrivesAfter == nil)
        #expect(file.notifications[1].leavesAfter == nil)
    }

    @Test func takesDecodesAndDefaultsToNil() throws {
        let file = try decode(#"{"notifications":[{"title":"a","takes":3},{"title":"b"}]}"#)
        #expect(file.notifications[0].takes == 3)
        #expect(file.notifications[1].takes == nil)
    }

    @Test func negativeTimingIsRejected() {
        #expect(throws: DemoFileError.self) {
            try decode(#"{"notifications":[{"arrivesAfter":-1}]}"#)
        }
        #expect(throws: DemoFileError.self) {
            try decode(#"{"notifications":[{"leavesAfter":-0.5}]}"#)
        }
    }

    @Test func timingOnAStackMemberIsRejected() {
        #expect(throws: DemoFileError.self) {
            try decode(#"{"notifications":[{"members":[{"title":"a","arrivesAfter":1}]}]}"#)
        }
        #expect(throws: DemoFileError.self) {
            try decode(#"{"notifications":[{"members":[{"title":"a","leavesAfter":1}]}]}"#)
        }
    }

    @Test func timingOnAStackItselfIsAllowed() throws {
        let file = try decode(
            #"{"notifications":[{"arrivesAfter":2,"members":[{"title":"a"}]}]}"#)
        #expect(file.notifications[0].arrivesAfter == 2)
    }
}
