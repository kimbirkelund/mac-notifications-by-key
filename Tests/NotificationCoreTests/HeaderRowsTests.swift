import CoreGraphics
import Testing

@testable import NotificationCore

@Suite struct HeaderRowsTests {
    private func rect(_ top: CGFloat, _ bottom: CGFloat) -> CGRect {
        CGRect(x: 0, y: top, width: 50, height: bottom - top)
    }

    @Test func rowBottomIsTheLargestBottomAmongOverlappingPieces() {
        let pieces = [rect(220, 240), rect(222, 245), rect(224, 238)]
        #expect(HeaderRows.bottom(above: 260, pieces: pieces) == 245)
    }

    @Test func nearestRowAboveTheContentIsChosen() {
        let pieces = [rect(100, 120), rect(220, 245), rect(400, 420)]
        #expect(HeaderRows.bottom(above: 260, pieces: pieces) == 245)
    }

    @Test func noRowAboveGivesNil() {
        #expect(HeaderRows.bottom(above: 50, pieces: [rect(100, 120)]) == nil)
        #expect(HeaderRows.bottom(above: 50, pieces: []) == nil)
    }
}
