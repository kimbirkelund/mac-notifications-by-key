import Testing

@testable import DemoNotifications

@Suite struct PendingEventsTests {
    private static func event(_ seq: Int) -> DemoEvent {
        DemoEvent(seq: seq, event: .arrived, state: DemoState(notifications: [], listOpen: false))
    }

    private static func filled(_ seqs: [Int]) -> PendingEvents {
        let pending = PendingEvents()
        for seq in seqs { pending.append(event(seq)) }
        return pending
    }

    @Test func takesEventsInTheOrderTheyWereAppended() {
        let pending = Self.filled([1, 2, 3])
        #expect(pending.take(through: 3).map(\.seq) == [1, 2, 3])
    }

    @Test func aPartialTakeLeavesLaterEventsQueuedForTheNextRender() {
        let pending = Self.filled([1, 2, 3, 4])
        #expect(pending.take(through: 2).map(\.seq) == [1, 2])
        #expect(pending.take(through: 2).isEmpty)
        pending.append(Self.event(5))
        #expect(pending.take(through: 4).map(\.seq) == [3, 4])
        #expect(pending.take(through: 5).map(\.seq) == [5])
    }

    @Test func takingThroughTheMaximumFlushesEverything() {
        let pending = Self.filled([1, 2, 3])
        #expect(pending.take(through: .max).map(\.seq) == [1, 2, 3])
        #expect(pending.take(through: .max).isEmpty)
    }

    @Test func nothingIsTakenBelowTheFirstQueuedSequence() {
        let pending = Self.filled([4, 5])
        #expect(pending.take(through: 3).isEmpty)
        #expect(pending.take(through: 5).map(\.seq) == [4, 5])
    }
}
