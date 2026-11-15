import Foundation

public struct DemoNotificationState: Equatable, Sendable, Codable {
    public var id: Int
    public var app: String?
    public var title: String?
    public var subtitle: String?
    public var body: String?
    public var actions: [String]
    public var collapsedStack: Bool
    public var hiddenMembers: Int
    public var replyField: Bool

    public init(
        id: Int, app: String? = nil, title: String? = nil, subtitle: String? = nil,
        body: String? = nil, actions: [String] = [], collapsedStack: Bool = false,
        hiddenMembers: Int = 0, replyField: Bool = false
    ) {
        self.id = id
        self.app = app
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.actions = actions
        self.collapsedStack = collapsedStack
        self.hiddenMembers = hiddenMembers
        self.replyField = replyField
    }
}

public struct DemoState: Equatable, Sendable, Codable {
    public var notifications: [DemoNotificationState]
    public var listOpen: Bool

    public init(notifications: [DemoNotificationState], listOpen: Bool) {
        self.notifications = notifications
        self.listOpen = listOpen
    }
}

public enum DemoEventKind: String, Sendable, Codable {
    case ready
    case arrived
    case departed
    case action
    case listOpened = "list-opened"
    case listClosed = "list-closed"
}

public enum DemoActionKind: String, Sendable, Codable {
    case press
    case close
    case named
    case expand
    case clearAll = "clear-all"
    case submitField = "submit-field"
}

public enum DemoOutcome: String, Sendable, Codable {
    case applied
    case kept
    case failed
}

public struct DemoEvent: Equatable, Sendable, Codable {
    public var seq: Int
    public var event: DemoEventKind
    public var state: DemoState
    public var id: Int?
    public var kind: DemoActionKind?
    public var action: String?
    public var outcome: DemoOutcome?
    public var error: String?
    public var text: String?

    public init(
        seq: Int, event: DemoEventKind, state: DemoState, id: Int? = nil,
        kind: DemoActionKind? = nil, action: String? = nil, outcome: DemoOutcome? = nil,
        error: String? = nil, text: String? = nil
    ) {
        self.seq = seq
        self.event = event
        self.state = state
        self.id = id
        self.kind = kind
        self.action = action
        self.outcome = outcome
        self.error = error
        self.text = text
    }
}
