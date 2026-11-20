import CoreGraphics
import Foundation

public enum HeaderRows {
    /// Bottom of the nearest header row ending at or above `contentTop`. Header
    /// pieces (heading and buttons) whose vertical spans overlap form one row.
    public static func bottom(above contentTop: CGFloat, pieces: [CGRect]) -> CGFloat? {
        var rows: [(top: CGFloat, bottom: CGFloat)] = []
        for piece in pieces.filter({ !$0.isEmpty }).sorted(by: { $0.minY < $1.minY }) {
            if let last = rows.last, piece.minY < last.bottom {
                rows[rows.count - 1].bottom = max(last.bottom, piece.maxY)
            } else {
                rows.append((piece.minY, piece.maxY))
            }
        }
        return rows.map(\.bottom).filter { $0 <= contentTop }.max()
    }
}
