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

    private func launchDemo(fixture: String, open: Bool = true) throws -> Process {
        let process = Process()
        process.executableURL = try #require(Self.demoBinary)
        process.arguments =
            (open ? ["--open"] : [])
            + [Self.repoRoot.appendingPathComponent("acceptance/fixtures/\(fixture)").path]
        try process.run()
        return process
    }

    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func readsTheStackFixtureThroughTheRealAdapter() throws {
        let demo = try launchDemo(fixture: "stack.json")
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(executableNamed: "demo-nc")

        let items = try ax.read(wait: 6)
        #expect(items.map(\.title) == ["Inbox", "Meeting"])
        #expect(items.map(\.app) == ["Mail", "Calendar"])
        #expect(items[0].isCollapsedStack)
        #expect(items[0].actions.contains("Clear All"))
        #expect(!items[0].actions.contains("Close"))
        #expect(!items[1].isCollapsedStack)
        #expect(items[1].actions.contains("Snooze"))
        #expect(items[1].actions.contains("Close"))

        let presented = try ax.readPresented()
        #expect(presented[0].extentBelow > 0)
    }

    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func opensAndClosesAClosedListThroughTheMenuBarToggle() throws {
        let demo = try launchDemo(fixture: "stack.json", open: false)
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(executableNamed: "demo-nc")

        let deadline = Date().addingTimeInterval(6)
        while ax.notificationCenterPID() == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        Thread.sleep(forTimeInterval: 1)
        #expect(!ax.isPanelOpen)
        while true {
            do {
                try ax.setPanelOpen(true)
                break
            } catch {
                guard Date() < deadline else { throw error }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        #expect(ax.isPanelOpen)
        #expect(try ax.read(wait: 6).map(\.title) == ["Inbox", "Meeting"])

        try ax.setPanelOpen(false)
        #expect(try ax.read(wait: 0).isEmpty)
        #expect(!ax.isPanelOpen)
    }

    @Test(.enabled(if: DemoNotificationCenterAXTests.available))
    func aListLaunchedOpenIsOpenAtOnceAndStaysOpen() throws {
        let demo = try launchDemo(fixture: "stack.json")
        defer { demo.terminate() }
        let ax = DefaultNotificationCenterAX(executableNamed: "demo-nc")

        let deadline = Date().addingTimeInterval(6)
        while !ax.isPanelOpen, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
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

        try ax.perform(action: "Reply", index: 0)

        let deadline = Date().addingTimeInterval(6)
        while panelTextFieldIdentifiers(pid).isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
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
        try ax.perform(action: "Reply", index: 0)
        let deadline = Date().addingTimeInterval(6)
        while !ax.panelShowsTextField(), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        #expect(ax.panelShowsTextField())

        try ax.focusPanelTextField()

        let pid = try #require(ax.notificationCenterPID())
        #expect(panelTextFields(pid).map(\.focused) == [true])
    }
}
