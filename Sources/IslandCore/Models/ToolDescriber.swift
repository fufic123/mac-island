import Foundation

/// Turns tool calls and Claude's messages into the short phrases the island shows.
public enum ToolDescriber {
    public static func describe(tool: String?, input: ToolInput?) -> String {
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
    public static func permissionAction(tool: String?, input: ToolInput?) -> String {
        switch tool {
        case "Bash": "Wants to run \(firstLine(input?.command) ?? "a command")"
        case "Edit", "MultiEdit", "NotebookEdit", "Write": "Wants to edit \(fileName(input) ?? "a file")"
        case "WebFetch": "Wants to fetch \(input?.url.flatMap { URL(string: $0)?.host } ?? "a page")"
        default: "Wants to use \(tool.map(shortName) ?? "a tool")"
        }
    }

    /// Peek text after the project name, e.g. "wants to run a command".
    public static func permissionPhrase(tool: String?) -> String {
        switch tool {
        case "Bash": "wants to run a command"
        case "Edit", "MultiEdit", "NotebookEdit", "Write": "wants to edit a file"
        case "WebFetch": "wants to fetch a page"
        default: "wants to use \(tool.map(shortName) ?? "a tool")"
        }
    }

    /// Permission panel title, e.g. "Run a command in realty-ads?".
    public static func permissionTitle(tool: String?, project: String) -> String {
        switch tool {
        case "Bash": "Run a command in \(project)?"
        case "Edit", "MultiEdit", "NotebookEdit", "Write": "Edit a file in \(project)?"
        case "WebFetch": "Fetch a page from \(project)?"
        default: "Use \(tool.map(shortName) ?? "a tool") in \(project)?"
        }
    }

    /// First meaningful line of a Markdown message, without the markup, for one-line previews.
    public static func summary(_ text: String?) -> String? {
        guard let line = text?.split(separator: "\n").lazy
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty && !$0.hasPrefix("```") })
        else { return nil }
        var s = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        while let first = s.first, "#-*> ".contains(first) { s.removeFirst() }
        return s.isEmpty ? nil : s
    }

    /// mcp__server__tool -> tool
    public static func shortName(_ tool: String) -> String {
        tool.components(separatedBy: "__").last ?? tool
    }

    public static func firstLine(_ text: String?, limit: Int = 60) -> String? {
        guard let line = text?.split(separator: "\n").first else { return nil }
        return line.count > limit ? line.prefix(limit) + "…" : String(line)
    }

    private static func fileName(_ input: ToolInput?) -> String? {
        (input?.filePath ?? input?.path).map { ($0 as NSString).lastPathComponent }
    }
}
