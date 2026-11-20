import Foundation

/// Chat titles Claude Desktop gives its Code sessions. Its sessions often run in a scratch folder
/// with a generated name, so the title is what the person recognizes. Each session is a JSON file
/// under claude-code-sessions/<account>/<org>/, holding the Claude Code session id and the title.
final class DesktopTitles: @unchecked Sendable {
    private let root: URL
    private var titles: [String: String] = [:]
    private var desktopIds: [String: String] = [:]
    private var checked: [URL: Date] = [:]

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")) {
        self.root = root
    }

    /// Re-reads only the session files that changed since the last call.
    func title(forSession id: String) -> String? {
        refresh()
        return titles[id]
    }

    /// Claude Desktop's own id for the session ("local_…"), which its claude://code links take.
    func desktopId(forSession id: String) -> String? {
        refresh()
        return desktopIds[id]
    }

    private func refresh() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                             options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in enumerator where url.pathExtension == "json" {
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  checked[url] != modified else { continue }
            checked[url] = modified
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["cliSessionId"] as? String else { continue }
            if let desktopId = json["sessionId"] as? String { desktopIds[id] = desktopId }
            guard let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            titles[id] = title
        }
    }
}
