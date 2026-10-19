import CoreGraphics
import Testing

@testable import NotificationCore

@Suite struct SelectionStateTests {
    @Test func initialSelectsFirstWhenNonEmpty() {
        #expect(SelectionState.initial(count: 3).selectedIndex == 0)
    }

    @Test func initialSelectsNothingWhenEmpty() {
        #expect(SelectionState.initial(count: 0).selectedIndex == nil)
    }

    @Test func moveDownSelectsNextOlder() {
        var s = SelectionState.initial(count: 3)
        s.moveDown()
        #expect(s.selectedIndex == 1)
    }

    @Test func moveUpSelectsNextNewer() {
        var s = SelectionState(count: 3, selectedIndex: 2)
        s.moveUp()
        #expect(s.selectedIndex == 1)
    }

    @Test func moveUpClampsAtFirst() {
        var s = SelectionState.initial(count: 3)
        s.moveUp()
        #expect(s.selectedIndex == 0)
    }

    @Test func moveDownClampsAtLast() {
        var s = SelectionState(count: 3, selectedIndex: 2)
        s.moveDown()
        #expect(s.selectedIndex == 2)
    }

    @Test func movingWhenEmptyKeepsNothingSelected() {
        var s = SelectionState.initial(count: 0)
        s.moveDown()
        s.moveUp()
        #expect(s.selectedIndex == nil)
    }

    @Test func clampedKeepsIndexWhenStillInRange() {
        let s = SelectionState(count: 5, selectedIndex: 2).clamped(to: 4)
        #expect(s.selectedIndex == 2)
        #expect(s.count == 4)
    }

    @Test func clampedMovesToLastWhenCountShrinksBelowIndex() {
        #expect(SelectionState(count: 5, selectedIndex: 4).clamped(to: 2).selectedIndex == 1)
    }

    @Test func clampedToZeroSelectsNothing() {
        #expect(SelectionState(count: 2, selectedIndex: 1).clamped(to: 0).selectedIndex == nil)
    }

    @Test func clampedFromEmptyToNonEmptySelectsFirst() {
        #expect(SelectionState.initial(count: 0).clamped(to: 3).selectedIndex == 0)
    }

    @Test func initNormalisesOutOfRangeIndex() {
        #expect(SelectionState(count: 3, selectedIndex: 9).selectedIndex == 2)
        #expect(SelectionState(count: 3, selectedIndex: -4).selectedIndex == 0)
        #expect(SelectionState(count: 0, selectedIndex: 1).selectedIndex == nil)
    }
}

@Suite struct SelectionMoveTests {
    @Test func applyingDownAndUpMovesLikeMoveDownAndMoveUp() {
        var s = SelectionState(count: 3, selectedIndex: 1)
        s.apply(.down)
        #expect(s.selectedIndex == 2)
        s.apply(.up)
        s.apply(.up)
        #expect(s.selectedIndex == 0)
    }

    @Test func applyingClampsAtBothEnds() {
        var s = SelectionState(count: 2, selectedIndex: 1)
        s.apply(.down)
        #expect(s.selectedIndex == 1)
        s.apply(.up)
        s.apply(.up)
        #expect(s.selectedIndex == 0)
    }
}

@Suite struct SelectionFollowingTests {
    private func note(_ title: String, index: Int = 0, y: Double = 0) -> PresentedNotification {
        PresentedNotification(
            item: NotificationItem(index: index, app: "App", title: title, body: "b"),
            frame: CGRect(x: 0, y: y, width: 10, height: 10))
    }

    private func list(_ titles: String...) -> [PresentedNotification] {
        titles.enumerated().map { note($1, index: $0, y: Double($0) * 10) }
    }

    @Test func arrivalAboveKeepsSameItemSelected() {
        let s = SelectionState(count: 2, selectedIndex: 1)
            .following(previous: list("a", "b"), current: list("new", "a", "b"))
        #expect(s.selectedIndex == 2)
        #expect(s.count == 3)
    }

    @Test func departureAboveKeepsSameItemSelected() {
        let s = SelectionState(count: 3, selectedIndex: 2)
            .following(previous: list("a", "b", "c"), current: list("b", "c"))
        #expect(s.selectedIndex == 1)
        #expect(s.count == 2)
    }

    @Test func matchIgnoresIndexFrameAndActions() {
        var moved = note("b", index: 7, y: 99)
        moved.item.actions = ["Name:Close"]
        let s = SelectionState(count: 2, selectedIndex: 1)
            .following(previous: list("a", "b"), current: [note("a"), moved])
        #expect(s.selectedIndex == 1)
    }

    @Test func departureOfSelectedFallsBackToClampedPosition() {
        let s = SelectionState(count: 3, selectedIndex: 1)
            .following(previous: list("a", "b", "c"), current: list("a", "c"))
        #expect(s.selectedIndex == 1)
        let last = SelectionState(count: 3, selectedIndex: 2)
            .following(previous: list("a", "b", "c"), current: list("a", "b"))
        #expect(last.selectedIndex == 1)
    }

    @Test func duplicatesPickNearestToPreviousPosition() {
        let s = SelectionState(count: 4, selectedIndex: 3)
            .following(
                previous: list("x", "y", "z", "d"),
                current: list("d", "x", "y", "z", "d"))
        #expect(s.selectedIndex == 4)
    }

    @Test func collapsedStackDiffersFromSameTextNotification() {
        var stack = note("a")
        stack.item.isCollapsedStack = true
        let s = SelectionState(count: 2, selectedIndex: 1)
            .following(previous: [note("a"), note("b")], current: [stack, note("b")])
        #expect(s.selectedIndex == 1)
        let t = SelectionState(count: 1, selectedIndex: 0)
            .following(previous: [note("a")], current: [note("z"), stack])
        #expect(t.selectedIndex == 0)
    }

    @Test func emptyCurrentSelectsNothing() {
        let s = SelectionState(count: 2, selectedIndex: 1)
            .following(previous: list("a", "b"), current: [])
        #expect(s.selectedIndex == nil)
        #expect(s.count == 0)
    }

    @Test func nilSelectionSelectsFirstWhenCurrentIsNonEmpty() {
        let s = SelectionState.initial(count: 0)
            .following(previous: [], current: list("a", "b"))
        #expect(s.selectedIndex == 0)
        #expect(s.count == 2)
    }

    @Test func nilSelectionStaysNilWhenCurrentIsEmpty() {
        let s = SelectionState.initial(count: 0).following(previous: [], current: [])
        #expect(s.selectedIndex == nil)
    }
}
