import Foundation

/// An open socket to a hook that is blocked waiting for the island's answer.
/// Whatever is sent becomes the hook's output; closing without sending means "no answer".
public final class HookConnection: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var isClosed = false
    private var watcher: DispatchSourceRead?

    public init(fd: Int32) {
        self.fd = fd
        var on: Int32 = 1
        // The hook may already be gone (e.g. answered in the terminal); don't die on SIGPIPE.
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { close() }

    public func send(_ data: Data) {
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

    /// Calls `handler` once if the hook goes away first (killed by Claude's hook timeout,
    /// the session quit), so a reply isn't offered to a hook that can no longer deliver it.
    public func onPeerClose(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed, watcher == nil else { return }
        let fd = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            var byte: UInt8 = 0
            let n = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
            // The hook never writes after its request, so readable means end of file (or an error).
            if n > 0 || (n < 0 && errno == EAGAIN) { return }
            self?.close()
            handler()
        }
        // The descriptor is closed only once the source lets go of it.
        source.setCancelHandler { Darwin.close(fd) }
        watcher = source
        source.resume()
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        if let watcher {
            watcher.cancel()
        } else {
            Darwin.close(fd)
        }
    }
}

/// What a blocked hook is waiting for.
public enum HookReply: Sendable {
    /// PermissionRequest: Allow / Deny.
    case permission(PermissionResponder)
    /// Background Stop hook: a typed reply that wakes Claude.
    case awaitReply(HookConnection)
}
