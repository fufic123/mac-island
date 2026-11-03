import Foundation

enum SessionStatus: Int, Comparable, Sendable {
    // Raw value is the sort priority: things that need the user come first.
    case needsPermission = 0
    case waitingForInput
    case working
    case done
    case idle

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var needsAttention: Bool { self == .needsPermission || self == .waitingForInput }
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
    /// What Claude is asking permission for, while `status == .needsPermission`.
    var pendingPermission: String?
    /// Full command / path the permission is for, shown in the Allow/Deny row.
    var permissionPreview: String?
    /// A hook is blocked waiting for Allow/Deny from the island.
    var awaitingDecision = false
    let startedAt: Date
    var lastEventAt: Date
    var finishedAt: Date?

    var projectName: String {
        cwd.map { ($0 as NSString).lastPathComponent } ?? "Unknown"
    }
}

enum ToolDescriber {
    static func describe(tool: String?, input: ToolInput?) -> String {
        guard let tool else { return "Working" }
        let file = (input?.filePath ?? input?.path).map { ($0 as NSString).lastPathComponent }
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
            // mcp__server__tool -> tool
            return tool.components(separatedBy: "__").last ?? tool
        }
    }

    private static func firstLine(_ text: String?) -> String? {
        guard let line = text?.split(separator: "\n").first else { return nil }
        return line.count > 60 ? line.prefix(60) + "…" : String(line)
    }
}
