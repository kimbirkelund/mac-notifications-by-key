import CoreGraphics

public enum PanelOpenDiagnostic {
    public static func describe(
        clock: CGRect?, pointer: CGPoint?, frontmost: (name: String, bundleID: String?)?
    ) -> String {
        let clockText = clock.map { "\(point($0.origin)) \(number($0.width))x\(number($0.height))" }
        let app = frontmost.map { app in app.bundleID.map { "\(app.name) (\($0))" } ?? app.name }
        return "clock at \(clockText ?? "unknown"), pointer at \(pointer.map(point) ?? "unknown"), "
            + "frontmost \(app ?? "unknown")"
    }

    private static func point(_ p: CGPoint) -> String { "(\(number(p.x)), \(number(p.y)))" }

    private static func number(_ value: CGFloat) -> String {
        value.isFinite && abs(value) < 1e15 && value == value.rounded()
            ? String(Int(value)) : String(Double(value))
    }
}
