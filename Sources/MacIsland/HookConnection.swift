import Foundation

/// An open socket to a hook that is blocked waiting for the island's answer.
/// Whatever is sent becomes the hook's output; closing without sending means "no answer".
final class HookConnection: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var isClosed = false

    init(fd: Int32) {
        self.fd = fd
        var on: Int32 = 1
        // The hook may already be gone (e.g. answered in the terminal); don't die on SIGPIPE.
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { close() }

    func send(_ data: Data) {
        lock.lock()
        if !isClosed {
            data.withUnsafeBytes { buf in
                var offset = 0
                while offset < buf.count {
                    let n = write(fd, buf.baseAddress! + offset, buf.count - offset)
                    if n <= 0 { break }
                    offset += n
                }
            }
        }
        lock.unlock()
        close()
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        Darwin.close(fd)
    }
}

/// What a blocked hook is waiting for.
enum HookReply: Sendable {
    /// PermissionRequest: Allow / Deny.
    case permission(PermissionResponder)
    /// Background Stop hook: a typed reply that wakes Claude.
    case awaitReply(HookConnection)
}
