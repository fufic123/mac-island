import Foundation

/// What all Claude Code conversations have cost today at API prices, from every transcript under
/// ~/.claude/projects (subagents included), counting only responses timestamped today.
public final class DailyCost: @unchecked Sendable {
    private struct FileState {
        var offset: UInt64 = 0
        var cost: Double = 0
        var seen: Set<String> = []
    }

    private let root: URL
    private var files: [String: FileState] = [:]
    private var day: Date?
    private let lock = NSLock()

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) {
        self.root = root
    }

    public func total(now: Date = .now) -> Double {
        lock.lock()
        defer { lock.unlock() }
        let start = Calendar.current.startOfDay(for: now)
        if day != start {
            day = start
            files = [:]
        }
        var total = 0.0
        for path in transcripts(modifiedSince: start) {
            var state = files[path] ?? FileState()
            if let read = TranscriptCost.readAppended(path, from: state.offset) {
                if read.rewritten { state = FileState() }
                state.offset = read.offset
                for entry in TranscriptCost.entries(in: read.data)
                where date(entry.timestamp).map({ $0 >= start }) ?? false && state.seen.insert(entry.key).inserted {
                    state.cost += entry.cost
                }
                files[path] = state
            }
            total += state.cost
        }
        return total
    }

    /// `<project>/<session>.jsonl` and `<project>/<session>/subagents/*.jsonl` touched today.
    private func transcripts(modifiedSince start: Date) -> [String] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        func recent(_ dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []).filter { url in
                url.pathExtension == "jsonl"
                    && ((try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) >= start
            }
        }
        var result: [String] = []
        for project in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for session in recent(project) {
                result.append(session.path)
                result += recent(session.deletingPathExtension().appendingPathComponent("subagents")).map(\.path)
            }
        }
        return result
    }

    // Used only under `lock`.
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func date(_ string: String?) -> Date? {
        string.flatMap { formatter.date(from: $0) }
    }
}
