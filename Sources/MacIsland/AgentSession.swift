import Foundation

enum SessionStatus: Int, Comparable, Sendable {
    // Raw value is the sort priority: things that need the user come first.
    case needsPermission = 0
    case question
    case working
    case done
    /// Claude's idle prompt ("waiting for your input"); shown like idle.
    case waitingForInput
    case idle

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The agent is blocked on the user (amber).
    var needsAttention: Bool { self == .needsPermission || self == .question }

    var group: SessionGroup {
        switch self {
        case .needsPermission, .question: .needsYou
        case .working: .running
        case .done: .finished
        case .waitingForInput, .idle: .idle
        }
    }
}

enum SessionGroup: Int, CaseIterable, Sendable {
    case needsYou, running, finished, idle

    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .running: "Running"
        case .finished: "Finished"
        case .idle: "Idle"
        }
    }
}

struct AgentSession: Identifiable, Sendable {
    let id: String
    var cwd: String?
    var gitBranch: String?
    var termProgram: String?
    var tty: String?
    var pid: Int32?
    var status: SessionStatus = .idle
    /// Human-readable current action, e.g. "Editing App.swift".
    var activity: String?
    /// Question text while `status == .question`.
    var question: String?

    /// Pending permission, while `status == .needsPermission`.
    var permissionTool: String?
    /// e.g. "Wants to run rm -rf node_modules".
    var pendingPermission: String?
    /// Full command / path the permission is for.
    var permissionPreview: String?
    /// Claude's own explanation of the tool call (`tool_input.description`).
    var permissionReason: String?
    var alwaysAllowLabel: String?
    /// A hook is blocked waiting for Allow/Deny from the island.
    var awaitingDecision = false
    /// Identifies the pending request, so a click can't land on a newer one than was shown.
    var permissionRequestId: UUID?
    var permissionRequestedAt: Date?

    let startedAt: Date
    var lastEventAt: Date
    /// Start of the current turn (last prompt).
    var turnStartedAt: Date?
    var finishedAt: Date?
    var lastTurnDuration: TimeInterval?

    var projectName: String {
        cwd.map { ($0 as NSString).lastPathComponent } ?? "Unknown"
    }

    /// cwd with the home folder shortened to "~".
    var displayPath: String? {
        guard let cwd else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }
}

enum ToolDescriber {
    static func describe(tool: String?, input: ToolInput?) -> String {
        guard let tool else { return "Working" }
        let file = fileName(input)
        switch tool {
        case "Bash":
            return "Running \(firstLine(input?.command) ?? "command")"
        case "Edit", "MultiEdit", "NotebookEdit":
            return "Editing \(file ?? "file")"
        case "Write":
            return "Writing \(file ?? "file")"
        case "Read":
            return "Reading \(file ?? "file")"
        case "Grep", "Glob":
            return "Searching \(input?.pattern ?? "files")"
        case "WebFetch":
            return "Fetching \(input?.url.flatMap { URL(string: $0)?.host } ?? "page")"
        case "WebSearch":
            return "Searching web for \(input?.query ?? "…")"
        case "Task", "Agent":
            return "Agent: \(input?.description ?? "subtask")"
        default:
            return "Using \(shortName(tool))"
        }
    }

    /// Row text for a pending permission, e.g. "Wants to run rm -rf node_modules".
    static func permissionAction(tool: String?, input: ToolInput?) -> String {
        switch tool {
        case "Bash": "Wants to run \(firstLine(input?.command) ?? "a command")"
        case "Edit", "MultiEdit", "NotebookEdit", "Write": "Wants to edit \(fileName(input) ?? "a file")"
        case "WebFetch": "Wants to fetch \(input?.url.flatMap { URL(string: $0)?.host } ?? "a page")"
        default: "Wants to use \(tool.map(shortName) ?? "a tool")"
        }
    }

    /// Peek text after the project name, e.g. "wants to run a command".
    static func permissionPhrase(tool: String?) -> String {
        switch tool {
        case "Bash": "wants to run a command"
        case "Edit", "MultiEdit", "NotebookEdit", "Write": "wants to edit a file"
        case "WebFetch": "wants to fetch a page"
        default: "wants to use \(tool.map(shortName) ?? "a tool")"
        }
    }

    /// Permission panel title, e.g. "Run a command in realty-ads?".
    static func permissionTitle(tool: String?, project: String) -> String {
        switch tool {
        case "Bash": "Run a command in \(project)?"
        case "Edit", "MultiEdit", "NotebookEdit", "Write": "Edit a file in \(project)?"
        case "WebFetch": "Fetch a page from \(project)?"
        default: "Use \(tool.map(shortName) ?? "a tool") in \(project)?"
        }
    }

    /// mcp__server__tool -> tool
    static func shortName(_ tool: String) -> String {
        tool.components(separatedBy: "__").last ?? tool
    }

    static func firstLine(_ text: String?, limit: Int = 60) -> String? {
        guard let line = text?.split(separator: "\n").first else { return nil }
        return line.count > limit ? line.prefix(limit) + "…" : String(line)
    }

    private static func fileName(_ input: ToolInput?) -> String? {
        (input?.filePath ?? input?.path).map { ($0 as NSString).lastPathComponent }
    }
}
