import CoreGraphics
import Testing

@testable import NotificationCore

@Suite struct CardFrameCorrectionTests {
    private func card(
        _ top: CGFloat, _ bottom: CGFloat, content: (CGFloat, CGFloat)? = nil,
        x: CGFloat = 3080, width: CGFloat = 344
    ) -> CardGeometry {
        CardGeometry(
            frame: CGRect(x: x, y: top, width: width, height: bottom - top),
            contentTop: content?.0, contentBottom: content?.1)
    }

    private func spans(_ cards: [CorrectedCard]) -> [[CGFloat]] {
        cards.map { [$0.frame.minY, $0.frame.maxY] }
    }

    @Test func dumpCardsComeBackInOrderWithSecondRebuiltFromFirstPadding() {
        let result = CardFrameCorrection.correct([
            card(42, 206, content: (135, 185)),
            card(42, 117, content: (56, 104)),
        ])
        #expect(result.map(\.source) == [1, 0])
        #expect(spans(result) == [[42, 117], [121, 198]])
    }

    @Test func expandedStackWrongCardsAreRebuiltAroundOwnContent() {
        let result = CardFrameCorrection.correct([
            card(42, 400, content: (236, 256)),
            card(42, 100, content: (56, 86)),
            card(42, 400, content: (200, 220)),
            card(110, 160, content: (124, 146)),
        ])
        #expect(result.map(\.source) == [1, 3, 2, 0])
        #expect(spans(result) == [[42, 100], [110, 160], [186, 222], [222, 270]])
    }

    @Test func wrongCardsAreClippedToNeighbours() {
        let result = CardFrameCorrection.correct([
            card(42, 400, content: (130, 150)),
            card(42, 400, content: (160, 180)),
            card(42, 100, content: (56, 86)),
        ])
        #expect(result.map(\.source) == [2, 0, 1])
        #expect(spans(result) == [[42, 100], [116, 150], [150, 194]])
    }

    @Test func wrongCardBetweenWellFormedCardsComesBackInContentOrder() {
        let result = CardFrameCorrection.correct([
            card(42, 100, content: (56, 86)),
            card(42, 300, content: (150, 180)),
            card(200, 260, content: (214, 246)),
        ])
        #expect(result.map(\.source) == [0, 1, 2])
        #expect(spans(result) == [[42, 100], [136, 194], [200, 260]])
    }

    @Test func everyCardWrongGetsContentExtent() {
        let result = CardFrameCorrection.correct([
            card(0, 300, content: (200, 230)),
            card(0, 300, content: (20, 50)),
        ])
        #expect(result.map(\.source) == [1, 0])
        #expect(spans(result) == [[20, 50], [200, 230]])
    }

    @Test func wellFormedCardsAreUntouchedAndKeepOrder() {
        let cards = [
            card(10, 70, content: (20, 60)),
            card(80, 140, content: (90, 130)),
            card(150, 210, content: (160, 200)),
        ]
        let result = CardFrameCorrection.correct(cards)
        #expect(result.map(\.source) == [0, 1, 2])
        #expect(result.map(\.frame) == cards.map(\.frame))
    }

    @Test func cardWithoutContentKeepsItsFrame() {
        let bare = card(100, 160)
        let result = CardFrameCorrection.correct([
            card(10, 70, content: (20, 60)), bare, card(170, 230, content: (180, 220)),
        ])
        #expect(result.map(\.source) == [0, 1, 2])
        #expect(result[1].frame == bare.frame)
    }

    @Test func contentlessCardWithListSizedFrameKeepsIt() {
        let list = card(0, 300)
        let result = CardFrameCorrection.correct([
            list, card(10, 70, content: (20, 60)),
        ])
        #expect(result.map(\.source) == [0, 1])
        #expect(result[0].frame == list.frame)
    }

    @Test func paddingIsNotTakenFromACardWhoseContentLiesOutsideItsFrame() {
        let result = CardFrameCorrection.correct([
            card(10, 30, content: (40, 50)),
            card(100, 160, content: (110, 150)),
            card(0, 400, content: (200, 220)),
        ])
        #expect(result.map(\.source) == [0, 1, 2])
        #expect(spans(result) == [[10, 30], [100, 160], [190, 230]])
    }

    @Test func xAndWidthNeverChange() {
        let result = CardFrameCorrection.correct([
            card(42, 206, content: (135, 185), x: 5, width: 111),
            card(42, 117, content: (56, 104), x: 7, width: 222),
        ])
        #expect(result.map(\.frame.minX) == [7, 5])
        #expect(result.map(\.frame.width) == [222, 111])
    }
}
