import CoreGraphics
import Foundation

public struct CardGeometry: Equatable, Sendable {
    public var frame: CGRect
    public var contentTop: CGFloat?
    public var contentBottom: CGFloat?

    public init(frame: CGRect, contentTop: CGFloat? = nil, contentBottom: CGFloat? = nil) {
        self.frame = frame
        self.contentTop = contentTop
        self.contentBottom = contentBottom
    }

    var content: (top: CGFloat, bottom: CGFloat)? {
        guard let contentTop, let contentBottom else { return nil }
        return (min(contentTop, contentBottom), max(contentTop, contentBottom))
    }
}

public struct CorrectedCard: Equatable, Sendable {
    public var source: Int
    public var frame: CGRect

    public init(source: Int, frame: CGRect) {
        self.source = source
        self.frame = frame
    }
}

public enum CardFrameCorrection {
    public static func correct(_ cards: [CardGeometry]) -> [CorrectedCard] {
        let contents = cards.map(\.content)

        let wrong = cards.indices.map { i -> Bool in
            let frame = cards[i].frame
            guard contents[i] != nil else { return false }
            return contents.indices.contains { j in
                guard j != i, let c = contents[j] else { return false }
                return frame.minY <= c.top && frame.maxY >= c.bottom
            }
        }

        let order = cards.indices.sorted {
            let a = contents[$0]?.top ?? cards[$0].frame.minY
            let b = contents[$1]?.top ?? cards[$1].frame.minY
            return (a, $0) < (b, $1)
        }

        let padding =
            order.lazy.compactMap { i -> (top: CGFloat, bottom: CGFloat)? in
                guard !wrong[i], let c = contents[i],
                    cards[i].frame.minY <= c.top, cards[i].frame.maxY >= c.bottom
                else { return nil }
                return (c.top - cards[i].frame.minY, cards[i].frame.maxY - c.bottom)
            }.first ?? (top: 0, bottom: 0)

        var vertical = cards.map { ($0.frame.minY, $0.frame.maxY) }
        for i in cards.indices where wrong[i] {
            let c = contents[i]!
            vertical[i] = (c.top - padding.top, c.bottom + padding.bottom)
        }

        for (position, i) in order.enumerated() where wrong[i] {
            let c = contents[i]!
            var (top, bottom) = vertical[i]
            if position > 0 {
                top = max(top, vertical[order[position - 1]].1)
            }
            if position + 1 < order.count {
                bottom = min(bottom, vertical[order[position + 1]].0)
            }
            vertical[i] = (min(top, c.top), max(bottom, c.bottom))
        }

        return order.map { i in
            var frame = cards[i].frame
            frame.origin.y = vertical[i].0
            frame.size.height = vertical[i].1 - vertical[i].0
            return CorrectedCard(source: i, frame: frame)
        }
    }
}
