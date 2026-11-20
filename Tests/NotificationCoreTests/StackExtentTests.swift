import CoreGraphics
import Testing

@testable import NotificationCore

@Suite struct StackExtentTests {
    private let frame = CGRect(x: 3080, y: 414, width: 344, height: 75)

    @Test func twoLayersBeforeAHeading() {
        #expect(
            StackExtent.below(
                frame: frame, nextEdge: 520, following: .heading, isCollapsedStack: true) == 16)
    }

    @Test func oneLayerBeforeAHeading() {
        let short = CGRect(x: 3080, y: 414, width: 344, height: 58)
        #expect(
            StackExtent.below(
                frame: short, nextEdge: 495, following: .heading, isCollapsedStack: true) == 8)
    }

    @Test func noLayersBeforeAHeading() {
        #expect(
            StackExtent.below(
                frame: frame, nextEdge: 504, following: .heading, isCollapsedStack: true) == 0)
    }

    @Test func twoLayersAtTheEndOfTheList() {
        let last = CGRect(x: 3080, y: 549, width: 344, height: 75)
        #expect(
            StackExtent.below(frame: last, nextEdge: 640, following: .end, isCollapsedStack: true)
                == 16)
    }

    @Test func oneLayerBeforeAnotherRow() {
        #expect(
            StackExtent.below(frame: frame, nextEdge: 503, following: .row, isCollapsedStack: true)
                == 8)
    }

    @Test func roundsToWholeLayers() {
        #expect(
            StackExtent.below(
                frame: frame, nextEdge: 518, following: .heading, isCollapsedStack: true) == 16)
        #expect(
            StackExtent.below(
                frame: frame, nextEdge: 523, following: .heading, isCollapsedStack: true) == 16)
    }

    @Test func clampsToAtMostTwoLayersAndNeverNegative() {
        #expect(
            StackExtent.below(
                frame: frame, nextEdge: 600, following: .heading, isCollapsedStack: true) == 16)
        #expect(
            StackExtent.below(
                frame: frame, nextEdge: 480, following: .heading, isCollapsedStack: true) == 0)
    }

    @Test func aPlainCardAboveAHeaderButtonGetsNoExtent() {
        let card = CGRect(x: 3080, y: 123, width: 344, height: 75)
        #expect(
            StackExtent.below(
                frame: card, nextEdge: 217, following: .heading, isCollapsedStack: false)
                == 0)
        let lower = CGRect(x: 3080, y: 327, width: 344, height: 77)
        #expect(
            StackExtent.below(
                frame: lower, nextEdge: 432, following: .heading, isCollapsedStack: false)
                == 0)
    }
}
