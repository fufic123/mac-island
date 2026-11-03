import Foundation

/// The open socket of a PermissionRequest hook that is waiting for Allow/Deny.
/// Whatever is written becomes the hook's stdout; closing without writing means "no decision".
final class PermissionResponder: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var isClosed = false

    init(fd: Int32) {
        self.fd = fd
        var on: Int32 = 1
        // The hook may already be gone (answered in the terminal); don't die on SIGPIPE.
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { close() }

    func allow() {
        reply(["behavior": "allow"])
    }

    func deny(message: String = "Denied from Mac Island") {
        reply(["behavior": "deny", "message": message])
    }

    /// Releases the hook without a decision, so Claude's own prompt handles it.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        Darwin.close(fd)
    }

    private func reply(_ decision: [String: String]) {
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ]
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: output) else { return close() }
        data.append(UInt8(ascii: "\n"))

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
}
