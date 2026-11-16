import ApplicationServices
import Foundation
import NotificationCore
import Testing

@testable import NotificationAX

/// AX-integration tier: reads a running `demo-nc` through the real adapter configured
/// for it. Gated on Accessibility trust and a built `demo-nc` binary.
@Suite(.serialized) struct DemoNotificationCenterAXTests {
    private final class BundleAnchor {}

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static var demoBinary: URL? {
        if let override = ProcessInfo.processInfo.environment["DEMO_NC_BIN"] {
            return URL(fileURLWithPath: override)
        }
        let sibling = Bundle(for: BundleAnchor.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("demo-nc")
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }

    static var available: Bool {
        NotificationCenterAccessFactory.make().isTrusted && demoBinary != nil
    }

    private struct DemoEvent: Decodable {
        struct Notification: Decodable {
            var id: Int
            var title: String?
            var replyField: Bool
        }
        struct State: Decodable {
            var listOpen: Bool
            var notifications: [Notification]
        }
        var seq: Int
        var event: String
        var id: Int?
        var kind: String?
        var action: String?
        var outcome: String?
        var state: State
    }

    private final class DemoProcess: @unchecked Sendable {
        let process = Process()
        private let condition = NSCondition()
        private var events: [DemoEvent] = []
        private var undecodable: [String] = []
        private var buffer = Data()

        init(arguments: [String]) throws {
            process.executableURL = try #require(DemoNotificationCenterAXTests.demoBinary)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.receive(handle.availableData)
            }
            try process.run()
        }

        private func receive(_ data: Data) {
            condition.lock()
            defer { condition.unlock() }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let event = try? JSONDecoder().decode(DemoEvent.self, from: Data(line)) {
                    events.append(event)
                } else {
                    undecodable.append(String(decoding: line, as: UTF8.self))
                }
            }
            condition.broadcast()
        }

        var lastSeq: Int {
            condition.lock()
            defer { condition.unlock() }
            return events.last?.seq ?? 0
        }

        @discardableResult
        func waitFor(
            timeout: TimeInterval = 6, afterSeq: Int = 0, _ matches: (DemoEvent) -> Bool
        ) throws -> DemoEvent {
            let deadline = Date().addingTimeInterval(timeout)
            condition.lock()
            defer { condition.unlock() }
            while true {
                if let event = events.first(where: { $0.seq > afterSeq && matches($0) }) {
                    return event
                }
                guard condition.wait(until: deadline) else {
                    let skipped = undecodable.isEmpty ? "" : "; undecodable lines: \(undecodable)"
                    throw NbkError.actionFailed(name: "await demo-nc event\(skipped)")
                }
            }
        }

        @discardableResult
        func awaitEvent(
            _ name: String, afterSeq: Int = 0, timeout: TimeInterval = 6
        ) throws -> DemoEvent {
            try waitFor(timeout: timeout, afterSeq: afterSeq) { $0.event == name }
        }

        func terminate() {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            process.terminate()
        }
    }

    private func launchDemo(fixture: String, open: Bool = true) throws -> DemoProcess {
        let demo = try DemoProcess(
            arguments: (open ? ["--open"] : [])
                + [Self.repoRoot.appendingPathComponent("acceptance/fixtures/\(fixture)").path])
        try demo.awaitEvent("ready")
        return demo
    }

    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func readsTheStackFixtureThroughTheRealAdapter() throws {
        let demo = try launchDemo(fixture: "stack.json")
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(executableNamed: "demo-nc")

        let items = try ax.read(wait: 6)
        #expect(items.map(\.title) == ["Inbox", "Meeting"])
        #expect(items.map(\.app) == ["Mail", "Calendar"])
        let stack = try #require(items.first)
        let meeting = try #require(items.dropFirst().first)
        #expect(stack.isCollapsedStack)
        #expect(stack.actions.contains("Clear All"))
        #expect(!stack.actions.contains("Close"))
        #expect(!meeting.isCollapsedStack)
        #expect(meeting.actions.contains("Snooze"))
        #expect(meeting.actions.contains("Close"))

        let presented = try ax.readPresented()
        let first = try #require(presented.first)
        #expect(first.extentBelow > 0)
    }

    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func opensAndClosesAClosedListThroughTheMenuBarToggle() throws {
        let demo = try launchDemo(fixture: "stack.json", open: false)
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(executableNamed: "demo-nc")

        let deadline = Date().addingTimeInterval(6)
        #expect(!ax.isPanelOpen)
        let beforeOpen = demo.lastSeq
        while true {
            do {
                try ax.setPanelOpen(true)
                break
            } catch {
                if (try? demo.awaitEvent("list-opened", afterSeq: beforeOpen, timeout: 0.5)) != nil
                {
                    break
                }
                guard Date() < deadline else { throw error }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        try demo.awaitEvent("list-opened", afterSeq: beforeOpen)
        #expect(ax.isPanelOpen)
        #expect(try ax.read(wait: 6).map(\.title) == ["Inbox", "Meeting"])

        let beforeClose = demo.lastSeq
        try ax.setPanelOpen(false)
        try demo.awaitEvent("list-closed", afterSeq: beforeClose)
        #expect(try ax.read(wait: 0).isEmpty)
        #expect(!ax.isPanelOpen)
    }

    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func aListLaunchedOpenIsOpenAtOnceAndStaysOpen() throws {
        let demo = try launchDemo(fixture: "stack.json")
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(executableNamed: "demo-nc")

        #expect(ax.isPanelOpen)
        try ax.setPanelOpen(true)
        #expect(ax.isPanelOpen)
    }

    private func panelTextFields(_ pid: pid_t) -> [(identifier: String?, focused: Bool)] {
        func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
            var value: AnyObject?
            AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return value
        }
        func fields(_ element: AXUIElement, depth: Int) -> [(identifier: String?, focused: Bool)] {
            guard depth < 12 else { return [] }
            let own: [(identifier: String?, focused: Bool)] =
                attr(element, kAXRoleAttribute) as? String == kAXTextFieldRole
                ? [
                    (
                        attr(element, kAXIdentifierAttribute) as? String,
                        attr(element, kAXFocusedAttribute) as? Bool == true
                    )
                ] : []
            let children = attr(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            return own + children.flatMap { fields($0, depth: depth + 1) }
        }
        let windows =
            attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
        return
            windows
            .filter { attr($0, kAXSubroleAttribute) as? String == kAXSystemDialogSubrole }
            .flatMap { fields($0, depth: 0) }
    }

    private func panelTextFieldIdentifiers(_ pid: pid_t) -> [String?] {
        panelTextFields(pid).map(\.identifier)
    }

    // RIM-27: a field action surfaces a text field in the panel without closing the notification.
    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func aFieldActionShowsATextFieldAndKeepsTheNotification() throws {
        let demo = try launchDemo(fixture: "reply.json")
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(executableNamed: "demo-nc")

        #expect(try ax.read(wait: 6).count == 2)
        let pid = try #require(ax.notificationCenterPID())
        #expect(panelTextFieldIdentifiers(pid).isEmpty)

        let beforeReply = demo.lastSeq
        try ax.perform(action: "Reply", index: 0)

        let event = try demo.waitFor(afterSeq: beforeReply) {
            $0.event == "action" && $0.action == "Reply"
        }
        #expect(event.outcome == "kept")
        #expect(panelTextFieldIdentifiers(pid) == ["reply"])
        #expect(try ax.read(wait: 0).count == 2)
    }

    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func aPanelWithoutATextFieldReportsNoneAndCannotFocusOne() throws {
        let demo = try launchDemo(fixture: "one.json")
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(executableNamed: "demo-nc")

        #expect(try ax.read(wait: 6).count == 1)
        #expect(!ax.panelShowsTextField())
        #expect(throws: NbkError.self) { try ax.focusPanelTextField() }
    }

    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func aShownTextFieldCanBeFocused() throws {
        let demo = try launchDemo(fixture: "reply.json")
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(executableNamed: "demo-nc")

        #expect(try ax.read(wait: 6).count == 2)
        let beforeReply = demo.lastSeq
        try ax.perform(action: "Reply", index: 0)
        try demo.waitFor(afterSeq: beforeReply) { $0.event == "action" && $0.action == "Reply" }
        #expect(ax.panelShowsTextField())

        try ax.focusPanelTextField()

        let pid = try #require(ax.notificationCenterPID())
        #expect(panelTextFields(pid).map(\.focused) == [true])
    }

    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func aNamedActionPerformedThroughTheAdapterIsReportedOnTheChannel() throws {
        let demo = try launchDemo(fixture: "reply.json")
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(executableNamed: "demo-nc")

        #expect(try ax.read(wait: 6).count == 2)
        let beforeArchive = demo.lastSeq
        try ax.perform(action: "Archive", index: 1)

        let event = try demo.waitFor(afterSeq: beforeArchive) {
            $0.event == "action" && $0.action == "Archive"
        }
        #expect(event.kind == "named")
        #expect(event.id == 1)
        #expect(event.outcome == "applied")
        #expect(event.state.notifications.map(\.title) == ["Ping"])
        #expect(try ax.read(wait: 0).map(\.title) == ["Ping"])
    }
}
