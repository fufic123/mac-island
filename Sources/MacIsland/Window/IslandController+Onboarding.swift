import AppKit
import IslandCore

/// First run in the island: connect the hooks (installing jq first if needed), wait for the first
/// session, and say so if the hooks later go missing.
extension IslandController {
    private var defaults: UserDefaults { .standard }

    func startOnboarding() {
        if ClaudeHooks.isInstalled {
            defaults.set(true, forKey: OnboardingDefaults.connectedKey)
            return
        }
        if defaults.bool(forKey: OnboardingDefaults.connectedKey) {
            model.onboarding = .disconnected
            return
        }
        guard !defaults.bool(forKey: OnboardingDefaults.declinedKey) else { return }
        offerConnect()
    }

    /// Opens the connect screen (or the jq step before it). Also the app menu's "Connect to Claude Code…".
    func offerConnect() {
        model.onboardingError = nil
        model.onboarding = ClaudeHooks.hasJQ ? .connect : .installJQ
        model.peek = nil
        model.isExpanded = true
    }

    func handleOnboarding(_ action: OnboardingAction) {
        switch action {
        case .notNow:
            defaults.set(true, forKey: OnboardingDefaults.declinedKey)
            model.onboarding = nil
            model.onboardingError = nil
            collapseUnderCursor()
        case .checkAgain:
            if ClaudeHooks.hasJQ {
                model.onboardingError = nil
                model.onboarding = .connect
            } else {
                model.onboardingError = "jq still isn't installed. Run the command above in Terminal, then check again."
            }
        case .copyJQCommand:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(OnboardingDefaults.jqCommand, forType: .string)
        case .showSettings:
            NSWorkspace.shared.activateFileViewerSelecting([ClaudeHooks.settingsFile])
        case .connect:
            connect()
        }
    }

    private func connect() {
        guard ClaudeHooks.hasJQ else {
            model.onboardingError = nil
            model.onboarding = .installJQ
            model.isExpanded = true
            return
        }
        guard !model.isConnecting else { return }
        let wasDisconnected = model.onboarding == .disconnected
        model.isConnecting = true
        model.onboardingError = nil
        Task { @MainActor in
            let error = await ClaudeHooks.install()
            model.isConnecting = false
            if let error {
                model.onboardingError = error
                return
            }
            defaults.set(true, forKey: OnboardingDefaults.connectedKey)
            defaults.removeObject(forKey: OnboardingDefaults.declinedKey)
            model.onboarding = wasDisconnected || model.hasSessions ? nil : .waiting
            collapseUnderCursor()
            reshowConnectedPeek()
        }
    }

    /// "Run claude in any terminal to begin" stays out until the first session appears.
    func reshowConnectedPeek() {
        guard model.onboarding == .waiting, !model.hasSessions, !model.isExpanded else { return }
        if case .connected? = model.peek?.kind { return }
        showPeek(Peek(kind: .connected))
    }

    /// The first session after connecting: the one time the island suggests hovering.
    func noticeFirstSession() {
        guard model.onboarding == .waiting, let first = model.store.sorted.first else { return }
        model.onboarding = nil
        showPeek(Peek(kind: .firstSession(project: first.projectName)))
    }

    /// Notices hooks disappearing from (or coming back to) the settings.
    func checkHooks() {
        guard !model.isConnecting else { return }
        if ClaudeHooks.isInstalled {
            defaults.set(true, forKey: OnboardingDefaults.connectedKey)
            if model.onboarding == .disconnected { model.onboarding = nil }
        } else if defaults.bool(forKey: OnboardingDefaults.connectedKey), model.onboarding == nil {
            model.onboarding = .disconnected
        }
    }
}
