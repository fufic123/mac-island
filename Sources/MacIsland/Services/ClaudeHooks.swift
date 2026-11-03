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
