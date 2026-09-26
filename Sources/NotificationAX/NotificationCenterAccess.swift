import Foundation
import NotificationCore

/// The domain seam: reading and acting on presented notifications, independent of
/// how a given macOS release lays out the Notification Center accessibility tree.
///
/// Callers depend on this protocol and obtain an implementation from
/// `NotificationCenterAccessFactory` (docs/constraints.md C-5); a new OS layout is an
/// added conformer plus a factory branch, never an edit to callers (C-3).
public protocol NotificationCenterAccess {
    var isTrusted: Bool { get }
    var isPanelOpen: Bool { get }
    func notificationCenterPID() -> pid_t?
    func read(wait: TimeInterval) throws -> [NotificationItem]
    func dismiss(index: Int) throws
    func press(index: Int) throws
    func perform(action displayName: String, index: Int) throws
    func setPanelOpen(_ open: Bool) throws
}
