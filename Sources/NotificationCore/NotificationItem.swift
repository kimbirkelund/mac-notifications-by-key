import Foundation

/// One presented notification, as surfaced to the CLI. Plain value type with no
/// Accessibility dependency, so it can be constructed and asserted in unit tests.
public struct NotificationItem: Codable, Equatable, Sendable {
    public var index: Int
    public var app: String?
    public var title: String?
    public var subtitle: String?
    public var body: String?
    public var actions: [String]

    public init(
        index: Int,
        app: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        body: String? = nil,
        actions: [String] = []
    ) {
        self.index = index
        self.app = app
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.actions = actions
    }
}

/// JSON rendering of the notification list (X-2: machine-readable output).
public enum Output {
    public static func json(_ items: [NotificationItem]) throws -> String {
        if items.isEmpty { return "[]" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(items)
        return String(decoding: data, as: UTF8.self)
    }
}

/// CLI argument errors, mapped to a usage exit code in `nbk`.
public enum ArgumentError: Error, Equatable, Sendable {
    case missingValue(flag: String)
    case invalidValue(flag: String, value: String)
    case negativeValue(flag: String, value: String)

    public var message: String {
        switch self {
        case .missingValue(let flag):
            return "\(flag) requires a value (seconds)."
        case .invalidValue(let flag, let value):
            return "\(flag) expects a number of seconds, got \"\(value)\"."
        case .negativeValue(let flag, let value):
            return "\(flag) must not be negative, got \"\(value)\"."
        }
    }

    /// 64 = EX_USAGE, matching the other argument-usage failures in `nbk`.
    public var exitCode: Int32 { 64 }
}

/// Parses the `--wait <seconds>` option (RNA-3). Absent → 0; present requires a
/// non-negative number. Kept pure so validation is unit-tested without the AX layer.
public enum WaitOption {
    public static func parse(_ tokens: [String]) throws -> TimeInterval {
        guard let i = tokens.firstIndex(of: "--wait") else { return 0 }
        guard i + 1 < tokens.count else { throw ArgumentError.missingValue(flag: "--wait") }
        let raw = tokens[i + 1]
        guard let seconds = Double(raw) else {
            throw ArgumentError.invalidValue(flag: "--wait", value: raw)
        }
        guard seconds >= 0 else { throw ArgumentError.negativeValue(flag: "--wait", value: raw) }
        return seconds
    }
}

/// Index selection (RNA-7: out-of-range is nil, never the wrong target).
public enum Selection {
    public static func at(_ items: [NotificationItem], _ n: Int) -> NotificationItem? {
        guard n >= 0, n < items.count else { return nil }
        return items[n]
    }
}

/// Accessibility surfaces actions as opaque strings like
/// `"Name:Close\nTarget:0x0\nSelector:(null)"`. These helpers extract the display
/// name and map a display name back to the raw AX action string. Kept here (pure)
/// so the parsing is unit-tested independently of the AX layer.
public enum ActionName {
    public static func display(fromAXAction raw: String) -> String {
        guard raw.hasPrefix("Name:") else { return raw }
        let afterPrefix = raw.dropFirst("Name:".count)
        return afterPrefix.split(separator: "\n", maxSplits: 1).first.map(String.init)
            ?? String(afterPrefix)
    }

    public static func axAction(named display: String, in rawActions: [String]) -> String? {
        rawActions.first { ActionName.display(fromAXAction: $0) == display }
    }
}
