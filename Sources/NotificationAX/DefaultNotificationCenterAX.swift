import AppKit
import ApplicationServices
import Darwin
import Foundation
import NotificationCore

/// Reads and acts on the live Notification Center accessibility tree.
///
/// Mechanism notes (probe-verified, macOS 26.5.1 — see docs/constraints.md C-3):
/// - Notification = `AXGroup` exposing an `AXPress` action, under the
///   "Notification Center" `AXWindow` → group → group → scroll area.
///   Children are `AXStaticText` with identifiers `title` / `subtitle` / `body`.
/// - The AX window exists only while a banner is on screen or the panel is open,
///   and a banner takes ~1s to render after delivery → `read(wait:)` polls.
/// - `Close` is a no-op unless the element is focused first → `dismiss` focuses,
///   settles, then performs `Close`.
public struct DefaultNotificationCenterAX: NotificationCenterAccess {
    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func notificationCenterPID() -> pid_t? {
        if let pid =
            NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
            .first?
            .processIdentifier
        {
            return pid
        }
        // Fallback: scan the process table directly. NSRunningApplication's snapshot
        // is occasionally empty in non-GUI process contexts (e.g. some test hosts);
        // libproc is independent of that.
        return pidByExecutablePath(containing: "CoreServices/NotificationCenter.app/")
    }

    private func pidByExecutablePath(containing needle: String) -> pid_t? {
        // C macros not exported to Swift: PROC_ALL_PIDS = 1, PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN.
        let allPids: UInt32 = 1
        let pathInfoMaxSize = 4 * 1024
        let maxBytes = proc_listpids(allPids, 0, nil, 0)
        guard maxBytes > 0 else { return nil }
        let capacity = Int(maxBytes) / MemoryLayout<pid_t>.size + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = proc_listpids(allPids, 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard written > 0 else { return nil }
        let count = Int(written) / MemoryLayout<pid_t>.size
        var pathBuffer = [CChar](repeating: 0, count: pathInfoMaxSize)
        for index in 0..<count {
            let pid = pids[index]
            guard pid > 0 else { continue }
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathInfoMaxSize))
            guard length > 0 else { continue }
            let bytes = pathBuffer[..<Int(length)].map { UInt8(bitPattern: $0) }
            if String(decoding: bytes, as: UTF8.self).contains(needle) { return pid }
        }
        return nil
    }

    // MARK: Read

    public func read(wait: TimeInterval = 0) throws -> [NotificationItem] {
        let pid = try requirePID()
        let deadline = Date().addingTimeInterval(max(0, wait))
        var elements = notificationElements(pid)
        while elements.isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            elements = notificationElements(pid)
        }
        return elements.enumerated().map { item(from: $0.element, index: $0.offset) }
    }

    // MARK: Act

    public func dismiss(index n: Int) throws {
        let element = try elementAt(n)
        // Focus-before-close: required, else Close silently no-ops.
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.3)
        try perform(displayName: "Close", on: element)
        // Close is asynchronous in Notification Center: it returns before the banner
        // leaves the tree. Wait (bounded) until it's gone so a subsequent `list`
        // reflects the dismissal.
        let pid = try requirePID()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline,
            notificationElements(pid).contains(where: { CFEqual($0, element) })
        {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    public func press(index n: Int) throws {
        let element = try elementAt(n)
        let r = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if r != .success { throw NbkError.actionFailed(name: "AXPress") }
    }

    public func perform(action displayName: String, index n: Int) throws {
        let element = try elementAt(n)
        try perform(displayName: displayName, on: element)
    }

    // MARK: - Internals

    private func requirePID() throws -> pid_t {
        guard isTrusted else { throw NbkError.notTrusted }
        guard let pid = notificationCenterPID() else { throw NbkError.noNotificationCenter }
        return pid
    }

    private func elementAt(_ n: Int) throws -> AXUIElement {
        let pid = try requirePID()
        let elements = notificationElements(pid)
        guard n >= 0, n < elements.count else {
            throw NbkError.indexOutOfRange(requested: n, count: elements.count)
        }
        return elements[n]
    }

    private func perform(displayName: String, on element: AXUIElement) throws {
        let raws = axActions(element)
        guard let raw = ActionName.axAction(named: displayName, in: raws) else {
            throw NbkError.unknownAction(
                name: displayName,
                available: raws.map(ActionName.display(fromAXAction:)).filter { $0 != "AXPress" }
            )
        }
        if AXUIElementPerformAction(element, raw as CFString) != .success {
            throw NbkError.actionFailed(name: displayName)
        }
    }

    /// Notification elements are `AXGroup`s exposing an `AXPress` action, found by
    /// structurally walking the app's windows (never a hardcoded index — C-3).
    private func notificationElements(_ pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        guard let windows = attr(app, kAXWindowsAttribute as String) as? [AXUIElement] else {
            return []
        }
        var found: [AXUIElement] = []
        func recurse(_ element: AXUIElement) {
            if axRole(element) == (kAXGroupRole as String),
                axActions(element).contains(kAXPressAction as String)
            {
                found.append(element)
            }
            for child in axChildren(element) { recurse(child) }
        }
        for window in windows { recurse(window) }
        return found
    }

    private func item(from element: AXUIElement, index: Int) -> NotificationItem {
        var title: String?
        var subtitle: String?
        var body: String?
        for child in axChildren(element) where axRole(child) == (kAXStaticTextRole as String) {
            let id = attr(child, kAXIdentifierAttribute as String) as? String
            let value = attr(child, kAXValueAttribute as String) as? String
            switch id {
            case "title": title = value
            case "subtitle": subtitle = value
            case "body": body = value
            default: break
            }
        }
        // Group AXDescription is "App, Title, Subtitle, Body" — first field is the app.
        let app = (attr(element, kAXDescriptionAttribute as String) as? String)?
            .split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let actions = axActions(element)
            .map(ActionName.display(fromAXAction:))
            .filter { $0 != (kAXPressAction as String) }
        return NotificationItem(
            index: index, app: app, title: title, subtitle: subtitle, body: body, actions: actions
        )
    }

    // MARK: AX primitives

    private func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
            ? value : nil
    }

    private func axActions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        return AXUIElementCopyActionNames(element, &names) == .success
            ? (names as? [String] ?? []) : []
    }

    private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        (attr(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private func axRole(_ element: AXUIElement) -> String {
        (attr(element, kAXRoleAttribute as String) as? String) ?? ""
    }
}
