import Foundation

/// What a Claude Code session has cost so far at API prices, from the token usage Claude Code
/// writes into its transcripts (the main one plus `<session>/subagents/*.jsonl`).
/// Files are read incrementally: only lines appended since the last call are parsed.
public final class TranscriptCost: @unchecked Sendable {
    private struct FileState {
        var offset: UInt64 = 0
        var cost: Double = 0
        var seen: Set<String> = []
    }

    private var files: [String: FileState] = [:]
    private let lock = NSLock()

    public init() {}

    /// Total USD for the session whose main transcript is at `transcriptPath`.
    public func cost(transcriptPath: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        var paths = [transcriptPath]
        let subagents = (transcriptPath as NSString).deletingPathExtension + "/subagents"
        if let names = try? FileManager.default.contentsOfDirectory(atPath: subagents) {
            paths += names.filter { $0.hasSuffix(".jsonl") }.map { subagents + "/" + $0 }
        }
        return paths.reduce(0) { $0 + update($1) }
    }

    public func forget(transcriptPath: String) {
        lock.lock()
        defer { lock.unlock() }
        let prefix = (transcriptPath as NSString).deletingPathExtension
        files = files.filter { $0.key != transcriptPath && !$0.key.hasPrefix(prefix + "/") }
    }

    private func update(_ path: String) -> Double {
        var state = files[path] ?? FileState()
        guard let handle = FileHandle(forReadingAtPath: path) else { return state.cost }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return state.cost }
        if size < state.offset { state = FileState() }  // rewritten
        guard size > state.offset else { return state.cost }
        try? handle.seek(toOffset: state.offset)
        guard let data = try? handle.readToEnd(),
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n"))
        else { return state.cost }
        // Only whole lines; a partially written last line is read next time.
        let complete = data[data.startIndex...lastNewline]
        state.offset += UInt64(complete.count)
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            // Cheap filter before JSON parsing: only assistant lines carry usage.
            guard line.count > 20,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let model = message["model"] as? String
            else { continue }
            // One API response is split into several lines (one per content block) that repeat
            // the same usage; count it once.
            let key = (message["id"] as? String ?? "") + "|" + (obj["requestId"] as? String ?? "")
            guard key != "|", state.seen.insert(key).inserted else { continue }
            state.cost += Self.price(model: model, usage: usage)
        }
        files[path] = state
        return state.cost
    }

    /// USD per million tokens: input, output, cache read. Cache writes are 1.25x input (5 min)
    /// and 2x input (1 hour). Anthropic API list prices.
    private static let prices: [(prefix: String, input: Double, output: Double, cacheRead: Double)] = [
        ("claude-fable-5-1", 10, 50, 0.25),
        ("claude-mythos-5-1", 10, 50, 0.25),
        ("claude-fable-5", 10, 50, 1),
        ("claude-mythos-5", 10, 50, 1),
        ("claude-opus-5-5", 4, 20, 0.20),
        ("claude-opus-5", 5, 25, 0.50),
        ("claude-opus-4-8", 5, 25, 0.50),
        ("claude-opus-4-7", 5, 25, 0.50),
        ("claude-opus-4-6", 5, 25, 0.50),
        ("claude-opus-4-5", 5, 25, 0.50),
        ("claude-opus-4", 15, 75, 1.50),
        ("claude-sonnet-5-5", 2, 10, 0.20),
        ("claude-sonnet-5", 2, 10, 0.20),
        ("claude-sonnet-4", 3, 15, 0.30),
        ("claude-haiku-5-5", 0.10, 0.50, 0.01),
        ("claude-haiku-4-5", 1, 5, 0.10),
        ("claude-3-5-haiku", 0.80, 4, 0.08),
    ]

    static func price(model: String, usage: [String: Any]) -> Double {
        let id = model.hasPrefix("anthropic.") ? String(model.dropFirst("anthropic.".count)) : model
        guard var p = prices.first(where: { id.hasPrefix($0.prefix) }) else { return 0 }
        func n(_ key: String, _ dict: [String: Any]? = nil) -> Double {
            ((dict ?? usage)[key] as? NSNumber)?.doubleValue ?? 0
        }
        let input = n("input_tokens"), output = n("output_tokens")
        let read = n("cache_read_input_tokens"), written = n("cache_creation_input_tokens")
        let split = usage["cache_creation"] as? [String: Any]
        let write1h = split.map { n("ephemeral_1h_input_tokens", $0) } ?? 0
        let write5m = split == nil ? written : n("ephemeral_5m_input_tokens", split)
        // Haiku 5.5 bills prompts over 100K tokens at a higher rate.
        if p.prefix == "claude-haiku-5-5", input + read + written > 100_000 {
            p = (p.prefix, 0.50, 2.50, 0.05)
        }
        // Fast mode costs twice the standard rate.
        let speed: Double = usage["speed"] as? String == "fast" ? 2 : 1
        let total = input * p.input + output * p.output + read * p.cacheRead
            + write5m * p.input * 1.25 + write1h * p.input * 2
        return total * speed / 1_000_000
    }
}
