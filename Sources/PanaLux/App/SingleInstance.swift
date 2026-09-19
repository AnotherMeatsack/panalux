import AppKit
import Darwin

/// One owner for the app's sockets, history and overlays, independent of its bundle path.
final class SingleInstance {
    static let shared = SingleInstance()
    private var descriptor: Int32 = -1

    func acquire(at path: String) -> Bool {
        guard descriptor == -1 else { return true }
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        descriptor = fd
        return true
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }

    static func enter() {
        guard !AppRuntime.isRenderingStills else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.panalux.app")
            .filter { $0.processIdentifier != getpid() && !$0.isTerminated }
        let path = AppPaths.supportDir.appendingPathComponent("instance.lock").path
        guard shared.acquire(at: path) else {
            others.first?.activate(options: [])
            exit(0)
        }
        // Older builds do not know the lock. Respect the already running copy.
        if let existing = others.first {
            existing.activate(options: [])
            exit(0)
        }
    }
}
