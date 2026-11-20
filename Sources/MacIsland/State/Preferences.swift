import Foundation
import Observation

/// What to do with sessions where nothing is happening (Claude finished and you've seen it, or
/// the terminal is just open).
enum IdleMode: String, CaseIterable, Identifiable {
    case hide, collapse, show
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hide: "Hide"
        case .collapse: "Collapse"
        case .show: "Show all"
        }
    }
}

/// How long a finished session keeps the amethyst light.
enum FinishedGlow: String, CaseIterable, Identifiable {
    case fiveMinutes, untilOpened
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fiveMinutes: "5 minutes"
        case .untilOpened: "Until opened"
        }
    }
}

/// User settings, kept in UserDefaults. Observable so the island redraws when they change.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Costs at API prices. Off by default: on a subscription plan nothing is actually billed.
    var showCost: Bool {
        didSet { defaults.set(showCost, forKey: "showCost") }
    }

    var idleMode: IdleMode {
        didSet { defaults.set(idleMode.rawValue, forKey: "idleMode") }
    }

    var finishedGlow: FinishedGlow {
        didSet { defaults.set(finishedGlow.rawValue, forKey: "finishedGlow") }
    }

    /// Finds sessions the hooks missed (started before the island, or in a client without hooks)
    /// from Claude Code's transcripts.
    var discoverSessions: Bool {
        didSet { defaults.set(discoverSessions, forKey: "discoverSessions") }
    }

    private init() {
        showCost = defaults.object(forKey: "showCost") as? Bool ?? false
        idleMode = defaults.string(forKey: "idleMode").flatMap(IdleMode.init) ?? .collapse
        finishedGlow = defaults.string(forKey: "finishedGlow").flatMap(FinishedGlow.init) ?? .untilOpened
        discoverSessions = defaults.object(forKey: "discoverSessions") as? Bool ?? true
    }
}
