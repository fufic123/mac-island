import Foundation

/// The Mac Island hooks in Claude Code's settings: whether they're there, and installing them
/// with the bundled install-hooks.sh (which needs jq).
enum ClaudeHooks {
    static let settingsFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    /// ~/.claude is outside the TCC-protected folders, so reading it never prompts.
    static var isInstalled: Bool {
        guard let text = try? String(contentsOf: settingsFile, encoding: .utf8) else { return false }
        return text.contains(".mac-island/hook.sh")
    }

    /// The hooks were installed by an older version: the reply hook lacks its long timeout, so
    /// Claude kills it after 10 minutes and replies typed later never arrive.
    static var isOutdated: Bool {
        if hookScriptIsStale { return true }
        guard let data = try? Data(contentsOf: settingsFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stop = (root["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        else { return false }
        let hooks = stop.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
        guard let awaitHook = hooks.first(where: {
            ($0["command"] as? String)?.contains(".mac-island/hook.sh --await-reply") == true
        }) else { return true }
        return ((awaitHook["timeout"] as? NSNumber)?.intValue ?? 0) < 86400
    }

    /// ~/.mac-island/hook.sh is a symlink (older developer installs; Claude Desktop can't follow
    /// it into ~/Documents) or differs from the hook bundled with this version of the app.
    private static var hookScriptIsStale: Bool {
        let installed = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mac-island/hook.sh")
        if (try? installed.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return true }
        guard let bundled = Bundle.main.url(forResource: "island-hook", withExtension: "sh"),
              let want = try? Data(contentsOf: bundled) else { return false }
        return (try? Data(contentsOf: installed)) != want
    }

    /// Where jq lives: built into macOS 15+, or Homebrew's on Apple silicon and Intel.
    private static let jqLocations = ["/usr/bin/jq", "/opt/homebrew/bin/jq", "/usr/local/bin/jq"]

    static var hasJQ: Bool {
        jqLocations.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs install-hooks.sh off the main thread. Returns an error message, or nil on success.
    static func install() async -> String? {
        guard let script = Bundle.main.url(forResource: "install-hooks", withExtension: "sh") else {
            return "install-hooks.sh is missing from the app."
        }
        return await Task.detached { run(script) }.value
    }

    private static func run(_ script: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--copy"]
        // Apps get a minimal PATH; add Homebrew's so a brew-installed jq is found.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return error.localizedDescription
        }
        guard process.terminationStatus != 0 else { return nil }
        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return message.isEmpty ? "The hooks couldn't be installed." : message
    }
}
