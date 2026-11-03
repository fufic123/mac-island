import Foundation

enum PermissionDecision: Sendable {
    case allow, deny, alwaysAllow
}

/// A PermissionRequest hook waiting for Allow/Deny; closing without an answer means
/// "no decision", so Claude's own prompt handles it.
final class PermissionResponder: @unchecked Sendable {
    private let connection: HookConnection
    /// Claude's `permission_suggestions`, sent back as `updatedPermissions` for "Always allow".
    private let suggestions: [Any]?
    /// Button label for the first suggestion, nil when there is none we can describe.
    let alwaysAllowLabel: String?

    init(connection: HookConnection, suggestions: [Any]? = nil) {
        self.connection = connection
        self.suggestions = suggestions
        self.alwaysAllowLabel = suggestions.flatMap(Self.label(for:))
    }

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

    func close() {
        connection.close()
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
        connection.send(data)
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
