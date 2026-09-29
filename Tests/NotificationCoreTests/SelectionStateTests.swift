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
