import Foundation
import Testing

@testable import InteractiveMode

@Suite struct InstanceLockTests {
    private func uniquePath() -> String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("nbk-interactive-test-\(UUID().uuidString).lock")
    }

    @Test func firstAcquireSucceeds() {
        let path = uniquePath()
        defer { unlink(path) }
        let lock = InstanceLock.acquire(path: path)
        #expect(lock.acquired)
        #expect(lock.ownerPID == getpid())
    }

    /// RIM-4: a second invocation sees the lock held and learns the owner's pid.
    @Test func secondAcquireReportsTheOwner() {
        let path = uniquePath()
        defer { unlink(path) }
        _ = InstanceLock.acquire(path: path)
        let second = InstanceLock.acquire(path: path)
        #expect(!second.acquired)
        #expect(second.ownerPID == getpid())
    }

    @Test func heldLockWithoutPidGivesNilOwner() throws {
        let path = uniquePath()
        defer { unlink(path) }
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        try #require(fd >= 0)
        defer { close(fd) }
        try #require(flock(fd, LOCK_EX | LOCK_NB) == 0)
        let lock = InstanceLock.acquire(path: path)
        #expect(!lock.acquired)
        #expect(lock.ownerPID == nil)
    }
}
