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
}
