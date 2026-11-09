import Foundation

public enum SessionStatus: Int, Comparable, Sendable, Codable {
    // Raw value is the sort priority: things that need the user come first.
    case needsPermission = 0
    case question
    case working
    case done
    /// Claude's idle prompt ("waiting for your input"); shown like idle.
    case waitingForInput
    case idle

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The agent is blocked on the user (amber).
    public var needsAttention: Bool { self == .needsPermission || self == .question }

    public var group: SessionGroup {
        switch self {
        case .needsPermission, .question: .needsYou
        case .working: .running
        case .done: .finished
        case .waitingForInput, .idle: .idle
        }
    }
}

public enum SessionGroup: Int, CaseIterable, Sendable {
    case needsYou, running, finished, idle

    public var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .running: "Running"
        case .finished: "Finished"
        case .idle: "Idle"
        }
    }
}

/// A subagent launched by a session's Task / Agent tool.
public struct Subagent: Identifiable, Sendable, Codable {
    public enum State: String, Sendable, Codable { case running, done, stopped }

    public let id: String
    public var type: String?
    /// What it was asked to do (the Task tool's description).
    public var task: String?
    /// Its current tool call while running.
    public var activity: String?
    public var state: State = .running
    public let startedAt: Date
    public var finishedAt: Date?
    /// First line of its final message.
    public var summary: String?

    public var title: String { task ?? type.map { $0 == "general-purpose" ? "Agent" : $0 } ?? "Agent" }
}

/// A launched Task call not yet matched to its SubagentStart.
public struct PendingAgentTask: Sendable, Codable {
    public var task: String?
    public var type: String?
}

public struct AgentSession: Identifiable, Sendable, Codable {
    public let id: String
    public var cwd: String?
    public var gitBranch: String?
    public var termProgram: String?
    /// Chat title, for sessions run by Claude Desktop.
    public var desktopTitle: String?
    public var tty: String?
    public var pid: Int32?
    public var status: SessionStatus = .idle
    /// Human-readable current action, e.g. "Editing App.swift".
    public var activity: String?
    /// Question text while `status == .question`.
    public var question: String?
    /// Claude's final text of the last turn.
    public var lastMessage: String?
    /// The background Stop hook is waiting, so a reply typed in the island reaches Claude.
    public var canReply = false
    /// Where Claude writes the conversation (under ~/.claude, readable without TCC prompts).
    public var transcriptPath: String?
    /// What the session has cost so far at API prices, subagents included.
    public var cost: Double?
    /// The user stopped the turn with Esc; Claude sends no Stop event for that.
    public var wasInterrupted = false

    /// Subagents of the current turn, in launch order.
    public var subagents: [Subagent] = []
    /// Descriptions of launched Task calls not yet matched to a SubagentStart.
    public var pendingAgentTasks: [PendingAgentTask] = []
    public var runningSubagents: Int { subagents.filter { $0.state == .running }.count }
    /// Claude Code's internal forks (prompt suggestion and the like): started without a Task call,
    /// so not shown as subagents.
    public var hiddenAgents: Set<String> = []
    /// Claude Code's suggested next prompt (its prompt_suggestion fork), offered as a one-click reply.
    public var suggestion: String?

    /// Pending permission, while `status == .needsPermission`.
    public var permissionTool: String?
    /// The subagent asking, if it isn't the main agent.
    public var permissionAgentId: String?
    /// e.g. "Wants to run rm -rf node_modules".
    public var pendingPermission: String?
    /// Full command / path the permission is for.
    public var permissionPreview: String?
    /// Claude's own explanation of the tool call (`tool_input.description`).
    public var permissionReason: String?
    public var alwaysAllowLabel: String?
    /// A hook is blocked waiting for Allow/Deny from the island.
    public var awaitingDecision = false
    /// Identifies the pending request, so a click can't land on a newer one than was shown.
    public var permissionRequestId: UUID?
    public var permissionRequestedAt: Date?

    public let startedAt: Date
    public var lastEventAt: Date
    /// Start of the current turn (last prompt).
    public var turnStartedAt: Date?
    public var finishedAt: Date?
    public var lastTurnDuration: TimeInterval?

    /// Clicking the row opens it in the island rather than jumping to the terminal. While Claude
    /// is busy the terminal is where things happen, so the click goes there.
    public var opensDetail: Bool {
        status != .working && !status.needsAttention && (canReply || lastMessage != nil)
    }

    /// Clock shown while nothing runs: the last turn's length, frozen.
    public var stoppedTime: TimeInterval {
        lastTurnDuration ?? lastEventAt.timeIntervalSince(startedAt)
    }

    public var projectName: String {
        if let desktopTitle { return desktopTitle }
        return cwd.map { ($0 as NSString).lastPathComponent } ?? "Unknown"
    }

    /// cwd with the home folder shortened to "~".
    public var displayPath: String? {
        guard let cwd else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }
}
