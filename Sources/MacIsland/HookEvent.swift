import Foundation

/// One message sent by `island-hook.sh`: the raw Claude Code hook payload plus terminal info.
struct HookEnvelope: Decodable, Sendable {
    let source: String
    let termProgram: String?
    let tty: String?
    let payload: ClaudeHookPayload
}

/// Subset of the Claude Code hook input we care about. Unknown fields are ignored.
struct ClaudeHookPayload: Decodable, Sendable {
    let hookEventName: String
    let sessionId: String
    let cwd: String?
    let transcriptPath: String?
    /// PreToolUse / PostToolUse / PermissionRequest.
    let toolName: String?
    /// Notification.
    let message: String?
    /// UserPromptSubmit.
    let prompt: String?
}

extension HookEnvelope {
    static func decode(_ data: Data) throws -> HookEnvelope {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(HookEnvelope.self, from: data)
    }
}
