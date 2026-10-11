import Foundation

public struct DemoAction: Equatable, Sendable, Codable {
    public var name: String
    public var closes: Bool

    public init(name: String, closes: Bool = true) {
        self.name = name
        self.closes = closes
    }

    private enum CodingKeys: String, CodingKey { case name, closes }

    public init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            self.init(name: name)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try c.decode(String.self, forKey: .name),
            closes: try c.decodeIfPresent(Bool.self, forKey: .closes) ?? true)
    }
}

public struct DemoNotification: Equatable, Sendable, Codable {
    public var app: String?
    public var title: String?
    public var subtitle: String?
    public var body: String?
    public var activateCloses: Bool
    public var actions: [DemoAction]

    public init(
        app: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        body: String? = nil,
        activateCloses: Bool = true,
        actions: [DemoAction] = []
    ) {
        self.app = app
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.activateCloses = activateCloses
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey {
        case app, title, subtitle, body, activateCloses, actions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            app: try c.decodeIfPresent(String.self, forKey: .app),
            title: try c.decodeIfPresent(String.self, forKey: .title),
            subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
            body: try c.decodeIfPresent(String.self, forKey: .body),
            activateCloses: try c.decodeIfPresent(Bool.self, forKey: .activateCloses) ?? true,
            actions: try c.decodeIfPresent([DemoAction].self, forKey: .actions) ?? [])
    }

    public func item(index: Int) -> NotificationItem {
        NotificationItem(
            index: index, app: app, title: title, subtitle: subtitle, body: body,
            actions: actions.map(\.name))
    }
}

public struct DemoFileError: Error, CustomStringConvertible, Equatable {
    public let description: String
}

public struct DemoFile: Equatable, Sendable, Codable {
    public var notifications: [DemoNotification]

    public init(notifications: [DemoNotification]) {
        self.notifications = notifications
    }

    public static func decode(from data: Data) throws -> DemoFile {
        do {
            return try JSONDecoder().decode(DemoFile.self, from: data)
        } catch let error as DecodingError {
            throw DemoFileError(description: describe(error))
        }
    }

    public static func load(from url: URL) throws -> DemoFile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DemoFileError(
                description: "cannot read \(url.path): \(error.localizedDescription)")
        }
        return try decode(from: data)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let ctx):
            return "invalid JSON: \(ctx.debugDescription)"
        case .keyNotFound(let key, let ctx):
            return "missing \"\(key.stringValue)\"\(location(ctx.codingPath))"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
            return "unexpected value\(location(ctx.codingPath))"
        @unknown default:
            return "invalid demo file"
        }
    }

    private static func location(_ path: [CodingKey]) -> String {
        path.isEmpty
            ? ""
            : " at "
                + path.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
}
