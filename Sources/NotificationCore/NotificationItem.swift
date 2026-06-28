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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(items)
        return String(decoding: data, as: UTF8.self)
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
