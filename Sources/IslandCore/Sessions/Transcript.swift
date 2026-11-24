import Foundation

/// Reads the end of a Claude Code transcript (JSONL under ~/.claude/projects).
public enum Transcript {
    /// Whether the latest conversation message is the marker Claude writes when the user presses Esc.
    public static func endsWithInterrupt(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return false }
        let start = size > 65_536 ? size - 65_536 : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return false }
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = obj["type"] as? String
            else { continue }
            guard type == "user" || type == "assistant" else { continue }
            guard type == "user", let message = obj["message"] as? [String: Any] else { return false }
            let texts: [String]
            if let text = message["content"] as? String {
                texts = [text]
            } else if let parts = message["content"] as? [[String: Any]] {
                texts = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            } else {
                texts = []
            }
            return texts.contains { $0.hasPrefix("[Request interrupted by user") }
        }
        return false
    }

    /// Claude Code's metadata for a subagent launched by the Task / Agent tool:
    /// "<session>/subagents/agent-<id>.meta.json" next to "<session>.jsonl".
    public static func subagentMeta(sessionTranscript: String?, agentId: String) -> (description: String, type: String?)? {
        guard let path = sessionTranscript, path.hasSuffix(".jsonl") else { return nil }
        let meta = String(path.dropLast(".jsonl".count)) + "/subagents/agent-\(agentId).meta.json"
        guard let data = FileManager.default.contents(atPath: meta),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let description = obj["description"] as? String, !description.isEmpty
        else { return nil }
        return (description, obj["agentType"] as? String)
    }

    public struct SubagentInfo: Sendable {
        public let id: String
        public let description: String
        public let type: String?
        /// When the subagent was launched (its metadata file's creation).
        public let started: Date
        public let modified: Date
        /// It handed its result back, or its last message ended the turn.
        public let finished: Bool
        /// The user stopped it (Esc), so it will write nothing more.
        public var interrupted = false
    }

    /// Every Task-launched subagent of a session, from "<session>/subagents/agent-<id>.meta.json".
    public static func subagents(sessionTranscript: String) -> [SubagentInfo] {
        guard sessionTranscript.hasSuffix(".jsonl") else { return [] }
        let dir = String(sessionTranscript.dropLast(".jsonl".count)) + "/subagents/"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.compactMap { name -> SubagentInfo? in
            guard name.hasPrefix("agent-"), name.hasSuffix(".meta.json") else { return nil }
            let id = String(name.dropFirst("agent-".count).dropLast(".meta.json".count))
            guard let meta = subagentMeta(sessionTranscript: sessionTranscript, agentId: id) else { return nil }
            let log = dir + "agent-\(id).jsonl"
            let modified = (try? FileManager.default.attributesOfItem(atPath: log))?[.modificationDate] as? Date ?? .distantPast
            let started = (try? FileManager.default.attributesOfItem(atPath: dir + name))?[.creationDate] as? Date ?? modified
            // Claude Code marks a subagent that handed its result back with "finished" in its metadata.
            let metaFinished = FileManager.default.contents(atPath: dir + name)
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["finished"] as? Bool == true
            let ending = ending(log)
            var info = SubagentInfo(id: id, description: meta.description, type: meta.type, started: started,
                                    modified: modified, finished: metaFinished || ending == .finished)
            info.interrupted = !info.finished && ending == .interrupted
            return info
        }
    }

    enum Ending: Equatable { case open, finished, interrupted }

    /// How a subagent's transcript ends: finished (its last message ended the turn, or it handed
    /// its result back with SubagentHandback), interrupted by the user, or still open.
    static func ending(_ path: String) -> Ending {
        guard let handle = FileHandle(forReadingAtPath: path) else { return .open }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return .open }
        try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        guard let data = try? handle.readToEnd() else { return .open }
        var handbackIds: Set<String> = []
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = obj["type"] as? String, type == "user" || type == "assistant"
            else { continue }
            let message = obj["message"] as? [String: Any]
            let parts = message?["content"] as? [[String: Any]] ?? []
            if type == "assistant" {
                if message?["stop_reason"] as? String == "end_turn" { return .finished }
                let handback = parts.contains {
                    $0["type"] as? String == "tool_use" && $0["name"] as? String == "SubagentHandback"
                        && ($0["id"] as? String).map(handbackIds.contains) ?? false
                }
                return handback ? .finished : .open
            }
            let texts = (message?["content"] as? String).map { [$0] }
                ?? parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            if texts.contains(where: { $0.hasPrefix("[Request interrupted") }) { return .interrupted }
            let results = parts.compactMap { $0["type"] as? String == "tool_result" ? $0["tool_use_id"] as? String : nil }
            guard !results.isEmpty else { return .open }
            // A tool result: finished only if it answers the handback call just before it.
            handbackIds.formUnion(results)
        }
        return .open
    }
}
