import Foundation
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "hooks")

/// Listens on a Unix domain socket; each connection carries one newline-terminated JSON envelope.
/// PermissionRequest connections stay open and are handed over as a `PermissionResponder`.
final class HookServer: @unchecked Sendable {
    static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mac-island/island.sock").path
    }

    private let path: String
    private let onEvent: @Sendable (HookEnvelope, PermissionResponder?) -> Void
    private let queue = DispatchQueue(label: "com.fufic123.macisland.hookserver")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    /// Upper bound for one message; hook payloads are a few KB at most.
    private let maxMessageSize = 1 << 20

    init(path: String = HookServer.defaultSocketPath, onEvent: @escaping @Sendable (HookEnvelope, PermissionResponder?) -> Void) {
        self.path = path
        self.onEvent = onEvent
    }

    func start() throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError.current }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: pathBytes) }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            let error = POSIXError.current
            close(fd)
            throw error
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { [path] in
            close(fd)
            unlink(path)
        }
        source.resume()
        acceptSource = source
        log.info("Listening on \(self.path, privacy: .public)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }
            handle(client)
        }
    }

    private func handle(_ client: Int32) {
        var keepOpen = false
        defer { if !keepOpen { close(client) } }
        // Accepted sockets inherit O_NONBLOCK on macOS; read blocking with a short timeout instead.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count < maxMessageSize {
            let n = read(client, &buffer, buffer.count)
            guard n > 0 else { break }
            data.append(contentsOf: buffer[0..<n])
            if buffer[n - 1] == UInt8(ascii: "\n") { break }
        }
        guard !data.isEmpty else { return }

        do {
            let envelope = try HookEnvelope.decode(data)
            log.info("\(envelope.payload.hookEventName, privacy: .public) session=\(envelope.payload.sessionId, privacy: .public)")
            if envelope.payload.hookEventName == "PermissionRequest" {
                keepOpen = true
                onEvent(envelope, PermissionResponder(fd: client))
            } else {
                onEvent(envelope, nil)
            }
        } catch {
            log.error("Bad hook message: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension POSIXError {
    static var current: POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
