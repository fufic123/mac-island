import AppKit
import SwiftUI

/// The Settings window: opened from the app menu (⌘,) and the Dock icon's menu.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    var onReconnect: () -> Void = {}
    var onCheckForUpdates: () -> Void = {}

    func show() {
        if window == nil {
            let view = SettingsView(
                prefs: Preferences.shared,
                onReconnect: { [weak self] in self?.onReconnect() },
                onCheckForUpdates: { [weak self] in self?.onCheckForUpdates() }
            )
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Mac Island Settings"
            window.styleMask = [.titled, .closable]
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    let prefs: Preferences
    let onReconnect: () -> Void
    let onCheckForUpdates: () -> Void

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section("What the island shows") {
                Picker("Idle sessions", selection: Binding(get: { prefs.idleMode }, set: { prefs.idleMode = $0 })) {
                    ForEach(IdleMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Idle: Claude finished and you've seen it, or the terminal is just open. Collapse folds them into a “+N idle” row.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Finished light", selection: Binding(get: { prefs.finishedGlow }, set: { prefs.finishedGlow = $0 })) {
                    ForEach(FinishedGlow.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Until opened keeps the purple light on until you open the session or jump to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show cost", isOn: Binding(get: { prefs.showCost }, set: { prefs.showCost = $0 }))
                Text("What sessions would cost at API prices. On a Pro, Max or Team plan nothing is billed per token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude Code") {
                Toggle("Find sessions the hooks missed",
                       isOn: Binding(get: { prefs.discoverSessions }, set: { prefs.discoverSessions = $0 }))
                Text("Reads Claude Code's transcripts and running claude processes, so sessions started before the island, or in clients without hooks, show up too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reconnect hooks…", action: onReconnect)
            }

            Section("Updates") {
                LabeledContent("Version", value: version)
                Button("Check for Updates…", action: onCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
