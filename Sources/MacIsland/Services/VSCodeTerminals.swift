import AppKit
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "vscode")

/// Opens the exact VS Code (or Cursor, Windsurf) integrated terminal a session runs in. VS Code has
/// no scripting for terminals, so a small bundled extension does it: the island writes Claude's
/// pid and its parents to ~/.mac-island/vscode-focus.json, the window whose terminal shell is one
/// of them shows that terminal and answers with its workspace, and the island opens that
/// workspace, which raises the window.
@MainActor
enum VSCodeTerminals {
    private nonisolated static let version = "1.0.0"
    private static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mac-island")

    /// `pids`: Claude's pid and its ancestors. `fallback` runs when no window claims the terminal
    /// (extension not installed yet, or the session isn't in an integrated terminal).
    static func focus(pids: [pid_t], app: URL, bundleId: String?, fallback: @escaping @MainActor () -> Void) {
        ensureInstalled(app: app, bundleId: bundleId)
        let id = UUID().uuidString
        let request: [String: Any] = ["id": id, "at": Int(Date().timeIntervalSince1970 * 1000), "pids": pids.map(Int.init)]
        guard let data = try? JSONSerialization.data(withJSONObject: request) else { return fallback() }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("vscode-focus.json")
        guard (try? data.write(to: file, options: .atomic)) != nil else { return fallback() }

        let answer = dir.appendingPathComponent("vscode-focus-\(id).json")
        Task {
            // The extension answers within a few hundred milliseconds when it's there.
            for _ in 0..<15 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let reply = try? Data(contentsOf: answer) else { continue }
                try? FileManager.default.removeItem(at: answer)
                let workspace = (try? JSONSerialization.jsonObject(with: reply) as? [String: Any])?["workspace"] as? String
                raise(app: app, workspace: workspace)
                log.info("terminal shown by the extension")
                return
            }
            log.info("no window claimed the terminal")
            fallback()
        }
    }

    /// Opening the window's own workspace with the app raises that window; nothing else does.
    private static func raise(app: URL, workspace: String?) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let workspace, workspace.hasPrefix("/"), FileManager.default.fileExists(atPath: workspace) {
            NSWorkspace.shared.open([URL(fileURLWithPath: workspace)], withApplicationAt: app, configuration: config)
        } else {
            NSWorkspace.shared.openApplication(at: app, configuration: config)
        }
    }

    /// Installs the bundled extension with the editor's own CLI once per editor and version.
    private static func ensureInstalled(app: URL, bundleId: String?) {
        let marker = dir.appendingPathComponent("vscode-extension-\(bundleId ?? app.lastPathComponent)")
        guard (try? String(contentsOf: marker, encoding: .utf8)) != version,
              let vsix = Bundle.main.url(forResource: "mac-island-terminals", withExtension: "vsix"),
              let cli = cli(in: app) else { return }
        Task.detached {
            let process = Process()
            process.executableURL = cli
            process.arguments = ["--install-extension", vsix.path, "--force"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return
            }
            if process.terminationStatus == 0 {
                try? version.write(to: marker, atomically: true, encoding: .utf8)
                log.info("installed the terminal extension")
            }
        }
    }

    /// The editor's command-line launcher: `code`, `cursor`, `windsurf`, `codium`…
    private static func cli(in app: URL) -> URL? {
        let bin = app.appendingPathComponent("Contents/Resources/app/bin")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: bin.path)) ?? []
        return names
            .filter { !$0.contains("tunnel") && !$0.hasPrefix(".") }
            .sorted()
            .map { bin.appendingPathComponent($0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
