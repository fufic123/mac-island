import Darwin
import Foundation

/// What a session's transcript says about it, for sessions the hooks missed: started before the
/// island or its hooks, run by a client that doesn't call hooks, or events lost while the island
/// was restarting.
public struct TranscriptState: Sendable {
    public enum Phase: Sendable, Equatable { case working, done, interrupted, idle }

    public let sessionId: String
    public let path: String
    public let modified: Date
    public var cwd: String?
    public var gitBranch: String?
    /// "cli", "claude-desktop", "sdk-ts", …
    public var entrypoint: String?
    public var phase: Phase = .idle
    /// Time of the last conversation message.
    public var lastAt: Date?
    /// Claude's final text, when the last turn ended.
    public var lastMessage: String?
    /// Time of the last prompt the user typed.
    public var lastPromptAt: Date?

    public init(sessionId: String, path: String, modified: Date, cwd: String? = nil, phase: Phase = .idle) {
        self.sessionId = sessionId
        self.path = path
        self.modified = modified
        self.cwd = cwd
        self.phase = phase
    }
}

public enum TranscriptScanner {
    public static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

    /// A working transcript that hasn't been written for this long belongs to a turn that died
    /// (or one blocked on a terminal prompt the island can't see); treat it as idle.
    public static let workingQuietLimit: TimeInterval = 10 * 60

    /// Transcripts of main conversations written within `window`. Subagent transcripts (in
    /// "<session>/subagents/") are skipped.
    public static func recent(within window: TimeInterval, now: Date = .now, root: URL = root) -> [TranscriptState] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: [.skipsHiddenFiles]) else { return [] }
        var result: [TranscriptState] = []
        for project in projects {
            // A folder's date changes when a file is added, not when one is appended to, so every
            // project folder is listed; it's only names and dates.
            guard let files = try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey],
                                                          options: [.skipsHiddenFiles]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      now.timeIntervalSince(modified) < window else { continue }
                let id = file.deletingPathExtension().lastPathComponent
                guard UUID(uuidString: id) != nil else { continue }
                // Claude Code appends bookkeeping lines (session owner, title, mode) to old
                // transcripts, so the file's date isn't activity: the last message's is.
                if let state = read(path: file.path, sessionId: id, modified: modified, now: now),
                   let at = state.lastAt, now.timeIntervalSince(at) < window {
                    result.append(state)
                }
            }
        }
        return result
    }

    private static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return (try? Date(s, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(s, strategy: .iso8601))
    }

    /// Reads the end of one transcript.
    public static func read(path: String, sessionId: String, modified: Date, now: Date = .now) -> TranscriptState? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }
        try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        guard let data = try? handle.readToEnd() else { return nil }

        var state = TranscriptState(sessionId: sessionId, path: path, modified: modified)
        var phaseKnown = false
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if state.cwd == nil, let cwd = obj["cwd"] as? String, !cwd.isEmpty { state.cwd = cwd }
            if state.gitBranch == nil, let branch = obj["gitBranch"] as? String { state.gitBranch = branch }
            if state.entrypoint == nil, let entry = obj["entrypoint"] as? String { state.entrypoint = entry }
            guard let type = obj["type"] as? String, type == "user" || type == "assistant",
                  obj["isSidechain"] as? Bool != true,
                  let message = obj["message"] as? [String: Any]
            else { continue }
            let texts = textParts(message["content"])
            let isToolResult = (message["content"] as? [[String: Any]])?.contains { $0["type"] as? String == "tool_result" } ?? false
            // Typed prompts only: tags (<system-reminder>, <task-notification>, <command-…>) are
            // written by Claude Code itself.
            let isPrompt = type == "user" && !isToolResult && obj["isMeta"] as? Bool != true
                && !texts.isEmpty
                && !texts.contains { $0.hasPrefix("<") || $0.hasPrefix("[Request interrupted") }
            if isPrompt, state.lastPromptAt == nil { state.lastPromptAt = date(obj["timestamp"]) }
            if !phaseKnown {
                // Local slash-command output and other meta lines say nothing about the turn.
                if type == "user", obj["isMeta"] as? Bool == true { continue }
                phaseKnown = true
                state.lastAt = date(obj["timestamp"])
                if type == "assistant" {
                    if message["stop_reason"] as? String == "end_turn" {
                        state.phase = .done
                        let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        state.lastMessage = text.isEmpty ? nil : text
                    } else {
                        state.phase = .working
                    }
                } else if texts.contains(where: { $0.hasPrefix("[Request interrupted") }) {
                    state.phase = .interrupted
                } else if texts.contains(where: { $0.hasPrefix("<command-") || $0.hasPrefix("<local-command") }) {
                    state.phase = .idle
                } else {
                    state.phase = .working
                }
            }
            if phaseKnown, state.lastPromptAt != nil, state.cwd != nil { break }
        }
        if state.phase == .working, now.timeIntervalSince(state.lastAt ?? .distantPast) > workingQuietLimit { state.phase = .idle }
        return state
    }

    private static func textParts(_ content: Any?) -> [String] {
        if let text = content as? String { return [text] }
        guard let parts = content as? [[String: Any]] else { return [] }
        return parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
    }
}

/// A running Claude Code process.
public struct ClaudeProcess: Sendable, Equatable {
    public let pid: Int32
    public let cwd: String
    /// "ttys004", or nil for one without a terminal (Claude Desktop runs it that way).
    public let tty: String?

    public init(pid: Int32, cwd: String, tty: String?) {
        self.pid = pid
        self.cwd = cwd
        self.tty = tty
    }
}

public enum ClaudeProcesses {
    /// Every process named "claude" owned by this user, with its working folder.
    public static func list() -> [ClaudeProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride + 16
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        size = count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        let n = size / MemoryLayout<kinfo_proc>.stride
        var result: [ClaudeProcess] = []
        for i in 0..<n {
            var info = procs[i]
            let name = withUnsafeBytes(of: &info.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            let pid = info.kp_proc.p_pid
            // The native install runs a binary named after its version
            // (~/.local/share/claude/versions/2.1.3), so p_comm alone misses it.
            guard name == "claude" || isClaudeBinary(pid) else { continue }
            guard let cwd = workingDirectory(of: pid) else { continue }
            let dev = info.kp_eproc.e_tdev
            var tty: String?
            if dev != -1, dev != 0, let cName = devname(dev, S_IFCHR) {
                let s = String(cString: cName)
                tty = s.hasPrefix("tty") ? s : nil
            }
            result.append(ClaudeProcess(pid: pid, cwd: cwd, tty: tty))
        }
        return result
    }

    private static func isClaudeBinary(_ pid: Int32) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let path = String(cString: buffer)
        return path.contains("/claude/versions/") || (path as NSString).lastPathComponent == "claude"
    }

    private static func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }
}
