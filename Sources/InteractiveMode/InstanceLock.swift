import Foundation

struct InstanceLock {
    let acquired: Bool
    let ownerPID: pid_t?

    static var defaultPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("nbk-interactive.lock")
    }

    /// On success the descriptor is deliberately never closed: the flock lives until the
    /// process dies, which is also what frees it after a crash.
    static func acquire(path: String = defaultPath) -> InstanceLock {
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return InstanceLock(acquired: true, ownerPID: nil) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            let pid = Array("\(getpid())".utf8)
            ftruncate(fd, 0)
            _ = pid.withUnsafeBufferPointer { pwrite(fd, $0.baseAddress, $0.count, 0) }
            return InstanceLock(acquired: true, ownerPID: getpid())
        }
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 32)
        let count = pread(fd, &buffer, buffer.count, 0)
        let text = count > 0 ? String(decoding: buffer[0..<count], as: UTF8.self) : ""
        return InstanceLock(
            acquired: false,
            ownerPID: pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}
