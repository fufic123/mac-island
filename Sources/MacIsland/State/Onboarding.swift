import Foundation

/// First-run steps shown in the island, from the design's V6-Onboarding.
enum OnboardingStep: Equatable {
    /// jq is missing; the hook installer needs it.
    case installJQ
    /// Ask before adding the hooks to ~/.claude/settings.json.
    case connect
    /// Connected; waiting for the first Claude session.
    case waiting
    /// The hooks were connected once and are gone from the settings.
    case disconnected
}

/// Buttons on the onboarding screens.
enum OnboardingAction {
    case notNow, connect, checkAgain, copyJQCommand, showSettings
}

enum OnboardingDefaults {
    /// Hooks were installed at some point, so their absence means "disconnected".
    static let connectedKey = "claudeHooksConnected"
    /// "Not now" on the connect screen; it isn't offered again automatically.
    static let declinedKey = "declinedClaudeHooks"
    static let jqCommand = "brew install jq"
}
