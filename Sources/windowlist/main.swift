import CoreGraphics
import Foundation

struct Bounds: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct WindowRow: Encodable {
    let owner: String
    let pid: Int
    let layer: Int
    let alpha: Double
    let bounds: Bounds
}

let infos =
    CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []

let rows = infos.map { info -> WindowRow in
    let rect =
        (info[kCGWindowBounds as String] as? NSDictionary)
        .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
    return WindowRow(
        owner: info[kCGWindowOwnerName as String] as? String ?? "",
        pid: info[kCGWindowOwnerPID as String] as? Int ?? 0,
        layer: info[kCGWindowLayer as String] as? Int ?? 0,
        alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
        bounds: Bounds(
            x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    )
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(rows))
FileHandle.standardOutput.write(Data("\n".utf8))
