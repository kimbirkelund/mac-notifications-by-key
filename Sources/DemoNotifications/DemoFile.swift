import Foundation
import NotificationCore

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
    public var members: [DemoNotification]
    public var arrivesAfter: TimeInterval?
    public var leavesAfter: TimeInterval?
    public var takes: TimeInterval?

    public init(
        app: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        body: String? = nil,
        activateCloses: Bool = true,
        actions: [DemoAction] = [],
        members: [DemoNotification] = [],
        arrivesAfter: TimeInterval? = nil,
        leavesAfter: TimeInterval? = nil,
        takes: TimeInterval? = nil
    ) {
        self.app = app
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.activateCloses = activateCloses
        self.actions = actions
        self.members = members
        self.arrivesAfter = arrivesAfter
        self.leavesAfter = leavesAfter
        self.takes = takes
    }

    private enum CodingKeys: String, CodingKey {
        case app, title, subtitle, body, activateCloses, actions, members
        case arrivesAfter, leavesAfter, takes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            app: try c.decodeIfPresent(String.self, forKey: .app),
            title: try c.decodeIfPresent(String.self, forKey: .title),
            subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
            body: try c.decodeIfPresent(String.self, forKey: .body),
            activateCloses: try c.decodeIfPresent(Bool.self, forKey: .activateCloses) ?? true,
            actions: try c.decodeIfPresent([DemoAction].self, forKey: .actions) ?? [],
            members: try c.decodeIfPresent([DemoNotification].self, forKey: .members) ?? [],
            arrivesAfter: try c.decodeIfPresent(TimeInterval.self, forKey: .arrivesAfter),
            leavesAfter: try c.decodeIfPresent(TimeInterval.self, forKey: .leavesAfter),
            takes: try c.decodeIfPresent(TimeInterval.self, forKey: .takes))
    }

    public var hasTiming: Bool { arrivesAfter != nil || leavesAfter != nil }

    public var isCollapsedStack: Bool { !members.isEmpty }

    public func item(index: Int) -> NotificationItem {
        NotificationItem(
            index: index, app: app, title: title, subtitle: subtitle, body: body,
            actions: actions.map(\.name), isCollapsedStack: isCollapsedStack)
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
        let file: DemoFile
        do {
            file = try JSONDecoder().decode(DemoFile.self, from: data)
        } catch let error as DecodingError {
            throw DemoFileError(description: describe(error))
        }
        let hasNestedMembers = file.notifications.contains {
            $0.members.contains(where: \.isCollapsedStack)
        }
        if hasNestedMembers {
            throw DemoFileError(description: "nested \"members\" are not supported")
        }
        for notification in file.notifications {
            if [notification.arrivesAfter, notification.leavesAfter].contains(where: {
                ($0 ?? 0) < 0
            }) {
                throw DemoFileError(
                    description: "\"arrivesAfter\" and \"leavesAfter\" must not be negative")
            }
            if notification.members.contains(where: \.hasTiming) {
                throw DemoFileError(
                    description:
                        "\"arrivesAfter\" and \"leavesAfter\" are not supported on \"members\"")
            }
        }
        return file
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
