import AppKit
import ServiceManagement
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "setup")

/// Makes a downloaded copy of the app work on its own: connects it to Claude Code (after asking)
/// and starts it at login. A developer install (scripts/install-app.sh) already does both.
@MainActor
enum FirstRunSetup {
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let settings = home.appendingPathComponent(".claude/settings.json")
    private static let launchAgent = home.appendingPathComponent("Library/LaunchAgents/com.fufic123.macisland.plist")
    private static let declinedKey = "declinedClaudeHooks"

    static func run() {
        registerLoginItem()
        if !hooksInstalled, !UserDefaults.standard.bool(forKey: declinedKey) {
            offerHooks()
        }
    }

    /// ~/.claude is outside the TCC-protected folders, so reading it never prompts.
    private static var hooksInstalled: Bool {
        guard let text = try? String(contentsOf: settings, encoding: .utf8) else { return false }
        return text.contains(".mac-island/hook.sh")
    }

    private static func registerLoginItem() {
        // The developer LaunchAgent already starts it; registering too would launch it twice.
        guard !FileManager.default.fileExists(atPath: launchAgent.path) else { return }
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            log.error("Login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func offerHooks() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Connect Mac Island to Claude Code?"
        alert.informativeText = """
            Mac Island adds hooks to ~/.claude/settings.json so your Claude Code sessions show up \
            in the island. A backup is saved as settings.json.bak. New Claude sessions pick them up.
            """
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return
        }
        installHooks()
    }

    private static func installHooks() {
        guard let script = Bundle.main.url(forResource: "install-hooks", withExtension: "sh") else {
            log.error("install-hooks.sh missing from the app bundle")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--copy"]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("install-hooks.sh failed to start: \(error.localizedDescription, privacy: .public)")
        }
        guard process.terminationStatus != 0 else { return }
        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let alert = NSAlert()
        alert.messageText = "Couldn't connect to Claude Code"
        alert.informativeText = message.isEmpty ? "install-hooks.sh exited with an error." : message
        alert.runModal()
    }
}
