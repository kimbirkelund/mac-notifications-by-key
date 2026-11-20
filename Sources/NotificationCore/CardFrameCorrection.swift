import CoreGraphics
import Foundation

public struct CardGeometry: Equatable, Sendable {
    public var frame: CGRect
    public var contentTop: CGFloat?
    public var contentBottom: CGFloat?
    public var app: String?
    public var headerBottom: CGFloat?

    public init(
        frame: CGRect, contentTop: CGFloat? = nil, contentBottom: CGFloat? = nil,
        app: String? = nil, headerBottom: CGFloat? = nil
    ) {
        self.frame = frame
        self.contentTop = contentTop
        self.contentBottom = contentBottom
        self.app = app
        self.headerBottom = headerBottom
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

        let suppliers = order.filter { i in
            guard !wrong[i], let c = contents[i] else { return false }
            return cards[i].frame.minY <= c.top && cards[i].frame.maxY >= c.bottom
        }

        func supplier(for i: Int) -> Int? {
            if let app = cards[i].app,
                let same = suppliers.first(where: { cards[$0].app == app })
            {
                return same
            }
            return suppliers.first
        }

        var vertical = cards.map { ($0.frame.minY, $0.frame.maxY) }
        var horizontal = cards.map { ($0.frame.minX, $0.frame.width) }
        for i in cards.indices where wrong[i] {
            let c = contents[i]!
            if let s = supplier(for: i), let sc = contents[s] {
                let f = cards[s].frame
                vertical[i] = (c.top - (sc.top - f.minY), c.bottom + (f.maxY - sc.bottom))
                horizontal[i] = (f.minX, f.width)
            } else {
                vertical[i] = (c.top, c.bottom)
            }
        }

        for (position, i) in order.enumerated() where wrong[i] {
            let c = contents[i]!
            var (top, bottom) = vertical[i]
            if position > 0 {
                top = max(top, vertical[order[position - 1]].1)
            }
            if let headerBottom = cards[i].headerBottom {
                top = max(top, headerBottom)
            }
            if position + 1 < order.count {
                bottom = min(bottom, vertical[order[position + 1]].0)
            }
            vertical[i] = (min(top, c.top), max(bottom, c.bottom))
        }

        return order.map { i in
            var frame = cards[i].frame
            frame.origin.x = horizontal[i].0
            frame.size.width = horizontal[i].1
            frame.origin.y = vertical[i].0
            frame.size.height = vertical[i].1 - vertical[i].0
            return CorrectedCard(source: i, frame: frame)
        }
    }
}
