import Foundation

/// One message sent by `island-hook.sh`: the raw Claude Code hook payload plus terminal info.
public struct HookEnvelope: Decodable, Sendable {
    public let source: String
    public let termProgram: String?
    public let tty: String?
    public let claudePid: Int32?
    /// Resolved by the hook, so the app never reads project folders (TCC-protected).
    public let gitBranch: String?
    /// Sent by the background Stop hook, which then waits for a typed reply.
    public let awaitReply: Bool?
    /// The waiting hook's own process, so the island notices when Claude kills it (hook timeout,
    /// session quit). The socket can't tell: nc half-closes it as soon as the request is sent.
    public let hookPid: Int32?
    public let payload: ClaudeHookPayload
}

/// Subset of the Claude Code hook input we care about. Unknown fields are ignored.
public struct ClaudeHookPayload: Decodable, Sendable {
    public let hookEventName: String
    public let sessionId: String
    public let cwd: String?
    public let transcriptPath: String?
    /// PreToolUse / PostToolUse / PermissionRequest.
    public let toolName: String?
    public let toolInput: ToolInput?
    /// Notification.
    public let message: String?
    public let notificationType: String?
    /// UserPromptSubmit.
    public let prompt: String?
    /// Stop / SubagentStop: the agent's final text.
    public let lastAssistantMessage: String?
    /// Set when the event comes from inside a subagent, and on SubagentStart / SubagentStop.
    public let agentId: String?
    public let agentType: String?
}

/// The handful of tool arguments used to describe what a tool call is doing.
public struct ToolInput: Decodable, Sendable {
    public let command: String?
    public let filePath: String?
    public let path: String?
    public let pattern: String?
    public let url: String?
    public let query: String?
    public let description: String?
    /// Task / Agent: which kind of subagent to launch.
    public let subagentType: String?
    /// AskUserQuestion.
    public let questions: [AskedQuestion]?
}

public struct AskedQuestion: Decodable, Sendable {
    public let question: String?
}

extension HookEnvelope {
    public static func decode(_ data: Data) throws -> HookEnvelope {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(HookEnvelope.self, from: data)
    }
}
