import CoreGraphics
import Foundation

/// How far a collapsed stack's layered cards reach below its front card. Notification
/// Center reports only the front card's frame, but the layers take up room in the
/// list, so the gap to whatever follows reveals them: 8 pt per layer, at most two.
public enum StackExtent {
    public enum Following: Equatable, Sendable {
        case heading
        case row
        case end
    }

    public static let layerHeight: CGFloat = 8
    public static let maxLayers = 2

    static func baseSpacing(before following: Following) -> CGFloat {
        switch following {
        case .heading: return 15
        case .row: return 6
        case .end: return 0
        }
    }

    public static func below(
        frame: CGRect, nextEdge: CGFloat, following: Following
    ) -> CGFloat {
        let room = nextEdge - baseSpacing(before: following) - frame.maxY
        let layers = Int((room / layerHeight).rounded())
        return CGFloat(min(max(layers, 0), maxLayers)) * layerHeight
    }
}
