import Foundation

public enum InstanceDecision: Equatable, Sendable {
    case run
    case focusExisting(pid_t?)

    public init(lockAcquired: Bool, ownerPID: pid_t?) {
        self = lockAcquired ? .run : .focusExisting(ownerPID)
    }
}
