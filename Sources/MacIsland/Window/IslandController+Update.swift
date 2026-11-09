import AppKit
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "update")

/// Looks for a newer release shortly after launch and every few hours, and offers it in the island.
extension IslandController {
    static let updateCheckInterval: TimeInterval = 6 * 60 * 60

    func startUpdateChecks() {
        model.installUpdate = { [weak self] in self?.installUpdate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkForUpdate() }
        Timer.scheduledTimer(withTimeInterval: Self.updateCheckInterval, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.checkForUpdate() }
        }
    }

    /// `manual`: from the app menu, so say so when there's nothing new.
    func checkForUpdate(manual: Bool = false) {
        Task {
            do {
                let update = try await Updater.check()
                if model.update != update { model.update = update; model.updateError = nil }
                if manual {
                    if update == nil { alert("Mac Island \(Updater.currentVersion) is the latest version.") }
                    else { offerConnectLike() }
                }
            } catch {
                log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                if manual { alert("Couldn't check for updates: \(error.localizedDescription)") }
            }
        }
    }

    private func installUpdate() {
        guard let update = model.update, !model.isUpdating else { return }
        model.isUpdating = true
        model.updateError = nil
        Task {
            do {
                try await Updater.install(update)
            } catch {
                model.isUpdating = false
                model.updateError = error.localizedDescription
            }
        }
    }

    /// Opens the island on the session list, where the update is offered.
    private func offerConnectLike() {
        model.selectedSessionId = nil
        model.isExpanded = true
    }

    private func alert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
