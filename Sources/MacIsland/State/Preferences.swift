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

/// The island's look. Crystal: an obsidian island lit only at its rim. Liquid Glass: a smoked
/// glass body over a blur of the desktop, with a specular edge and slow liquid color.
enum Design: String, CaseIterable, Identifiable {
    case crystal, liquidGlass
    var id: String { rawValue }
    var title: String {
        switch self {
        case .crystal: "Crystal"
        case .liquidGlass: "Liquid Glass"
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

    /// The subscription's 5-hour and weekly usage limits under the session list.
    var showLimits: Bool {
        didSet { defaults.set(showLimits, forKey: "showLimits") }
    }

    /// Asks Anthropic for the limits every minute with Claude Code's sign-in, instead of waiting
    /// for Claude Code's status line to report them.
    var limitsFromAccount: Bool {
        didSet { defaults.set(limitsFromAccount, forKey: "limitsFromAccount") }
    }

    var design: Design {
        didSet {
            defaults.set(design.rawValue, forKey: "design")
            Theme.design = design
        }
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
        showLimits = defaults.object(forKey: "showLimits") as? Bool ?? true
        limitsFromAccount = defaults.object(forKey: "limitsFromAccount") as? Bool ?? true
        let design = defaults.string(forKey: "design").flatMap(Design.init) ?? .crystal
        self.design = design
        Theme.design = design
        idleMode = defaults.string(forKey: "idleMode").flatMap(IdleMode.init) ?? .collapse
        finishedGlow = defaults.string(forKey: "finishedGlow").flatMap(FinishedGlow.init) ?? .untilOpened
        discoverSessions = defaults.object(forKey: "discoverSessions") as? Bool ?? true
    }
}
