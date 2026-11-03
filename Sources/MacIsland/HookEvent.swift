import Foundation

/// One message sent by `island-hook.sh`: the raw Claude Code hook payload plus terminal info.
struct HookEnvelope: Decodable, Sendable {
    let source: String
    let termProgram: String?
    let tty: String?
    let claudePid: Int32?
    /// Resolved by the hook, so the app never reads project folders (TCC-protected).
    let gitBranch: String?
    /// Sent by the background Stop hook, which then waits for a typed reply.
    let awaitReply: Bool?
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
    let toolInput: ToolInput?
    /// Notification.
    let message: String?
    let notificationType: String?
    /// UserPromptSubmit.
    let prompt: String?
    /// Stop / SubagentStop: the agent's final text.
    let lastAssistantMessage: String?
    /// Set when the event comes from inside a subagent, and on SubagentStart / SubagentStop.
    let agentId: String?
    let agentType: String?
}

/// The handful of tool arguments used to describe what a tool call is doing.
struct ToolInput: Decodable, Sendable {
    let command: String?
    let filePath: String?
    let path: String?
    let pattern: String?
    let url: String?
    let query: String?
    let description: String?
    /// Task / Agent: which kind of subagent to launch.
    let subagentType: String?
    /// AskUserQuestion.
    let questions: [AskedQuestion]?
}

struct AskedQuestion: Decodable, Sendable {
    let question: String?
}

extension HookEnvelope {
    static func decode(_ data: Data) throws -> HookEnvelope {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(HookEnvelope.self, from: data)
    }
}
