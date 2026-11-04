import Foundation
import ServiceManagement
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "setup")

/// Starts the app at login.
enum LoginItem {
    static func register() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            log.error("Login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
