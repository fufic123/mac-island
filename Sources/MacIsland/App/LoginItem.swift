import Foundation
import ServiceManagement
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "setup")

/// Starts a downloaded copy of the app at login. A developer install (scripts/install-app.sh)
/// uses a LaunchAgent instead, and registering both would launch it twice.
enum LoginItem {
    private static let launchAgent = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.fufic123.macisland.plist")

    static func register() {
        guard !FileManager.default.fileExists(atPath: launchAgent.path) else { return }
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            log.error("Login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
