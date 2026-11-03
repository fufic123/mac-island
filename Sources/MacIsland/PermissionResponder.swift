import Foundation

enum PermissionDecision: Sendable {
    case allow, deny, alwaysAllow
}

/// The open socket of a PermissionRequest hook that is waiting for Allow/Deny.
/// Whatever is written becomes the hook's stdout; closing without writing means "no decision".
final class PermissionResponder: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var isClosed = false
    /// Claude's `permission_suggestions`, sent back as `updatedPermissions` for "Always allow".
    private let suggestions: [Any]?
    /// Button label for the first suggestion, nil when there is none we can describe.
    let alwaysAllowLabel: String?

    init(fd: Int32, suggestions: [Any]? = nil) {
        self.fd = fd
        self.suggestions = suggestions
        self.alwaysAllowLabel = suggestions.flatMap(Self.label(for:))
        var on: Int32 = 1
        // The hook may already be gone (answered in the terminal); don't die on SIGPIPE.
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { close() }

    /// The rule "Always allow" adds, for the confirmation peek.
    var alwaysAllowRule: String? {
        guard let first = suggestions?.first as? [String: Any],
              let rule = (first["rules"] as? [[String: Any]])?.first
        else { return nil }
        return (rule["ruleContent"] as? String) ?? (rule["toolName"] as? String)
    }

    func respond(_ decision: PermissionDecision) {
        switch decision {
        case .allow:
            reply(["behavior": "allow"])
        case .deny:
            reply(["behavior": "deny", "message": "Denied from Mac Island"])
        case .alwaysAllow:
            // Send back only the suggestion the button described, nothing the user didn't see.
            var body: [String: Any] = ["behavior": "allow"]
            if alwaysAllowLabel != nil, let first = suggestions?.first { body["updatedPermissions"] = [first] }
            reply(body)
        }
    }

    /// Releases the hook without a decision, so Claude's own prompt handles it.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        Darwin.close(fd)
    }

    private func reply(_ decision: [String: Any]) {
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

    private static func label(for suggestions: [Any]) -> String? {
        guard let first = suggestions.first as? [String: Any] else { return nil }
        switch first["type"] as? String {
        case "addRules":
            guard let rule = (first["rules"] as? [[String: Any]])?.first else { return nil }
            let what = (rule["ruleContent"] as? String) ?? (rule["toolName"] as? String) ?? "this"
            let scoped = ["localSettings", "projectSettings"].contains(first["destination"] as? String ?? "")
            return "Always allow \(what)\(scoped ? " in this project" : "")"
        case "setMode" where first["mode"] as? String == "acceptEdits":
            return "Allow all edits this session"
        default:
            return nil
        }
    }
}
