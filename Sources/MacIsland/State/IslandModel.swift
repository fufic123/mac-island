import Observation
import IslandCore
import CoreGraphics
import Foundation

/// A short-lived expansion announcing an event, without hovering.
struct Peek: Equatable {
    enum Kind: Equatable {
        case permission(project: String, phrase: String)
        case question(project: String)
        case done(sessionId: String, project: String, duration: TimeInterval?, summary: String?)
        case replied(project: String, text: String)
        case allowed(project: String, detail: String)
        case denied
        case ruleAdded(rule: String, project: String)
        /// Onboarding: hooks connected, waiting for the first session.
        case connected
        /// Onboarding: the first session appeared; the one time hovering is suggested.
        case firstSession(project: String)
    }

    let id = UUID()
    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    init(_ signal: IslandSignal) {
        switch signal {
        case let .permission(project, phrase): kind = .permission(project: project, phrase: phrase)
        case let .question(project): kind = .question(project: project)
        case let .done(sessionId, project, duration, summary):
            kind = .done(sessionId: sessionId, project: project, duration: duration, summary: summary)
        case let .replied(project, text): kind = .replied(project: project, text: text)
        case let .allowed(project, detail): kind = .allowed(project: project, detail: detail)
        case .denied: kind = .denied
        case let .ruleAdded(rule, project): kind = .ruleAdded(rule: rule, project: project)
        }
    }

    /// How long it stays out before folding back.
    var duration: TimeInterval {
        switch kind {
        case .permission, .question: 6
        // Claude's closing line stays out for a minute, until it's hovered (which opens it) or
        // the session starts working again.
        case .done: 60
        case .allowed, .denied: 1.2
        case .ruleAdded, .replied: 5
        // Stays until the first session shows up.
        case .connected: 24 * 3600
        case .firstSession: 8
        }
    }

    var gem: Gem {
        switch kind {
        case .permission, .question: .amber
        case .done: .amethyst
        case .allowed, .ruleAdded, .replied: .emerald
        case .denied, .connected: .obsidian
        case .firstSession: .emerald
        }
    }

    /// A finished turn shows Claude's closing line, which takes up to two lines.
    var isTall: Bool {
        if case .done(_, _, _, let summary?) = kind { return !summary.isEmpty }
        if case .firstSession = kind { return true }
        return false
    }

    /// Session a hover should open in detail.
    var sessionId: String? {
        if case let .done(sessionId, _, _, _) = kind { return sessionId }
        return nil
    }
}

@MainActor
@Observable
final class IslandModel {
    let store: SessionStore
    var isExpanded = false
    var peek: Peek?
    var notchWidth: CGFloat = NotchGeometry.fallbackSize.width
    var notchHeight: CGFloat = NotchGeometry.fallbackSize.height
    /// Session rows in the island view's coordinate space, for hover highlighting. Not observed:
    /// rows report new frames on every animation frame, and re-rendering for that drops frames.
    @ObservationIgnored var rowFrames: [String: CGRect] = [:]
    /// Row under the cursor; changes only when the cursor crosses into another row.
    var hoveredSessionId: String?
    /// Natural height of the open panel's scrollable body.
    var panelBodyHeight: CGFloat = 0
    /// Session opened in detail (last message and reply), nil for the list.
    var selectedSessionId: String? {
        didSet {
            if oldValue != selectedSessionId {
                replyDraft = ""
                showsFullMessage = false
            }
        }
    }
    /// The reply field has keyboard focus; the island stays open while typing.
    var isComposing = false
    /// Text being typed in the reply field. Cleared when a different session is opened.
    var replyDraft = ""
    /// The reply screen shows Claude's message cut to its first words until this is set.
    var showsFullMessage = false
    /// The cursor is over the session screen's "open" button.
    var hoversOpenButton = false
    /// Its tooltip, shown after the usual macOS hover delay.
    var showsOpenHint = false
    /// First-run step shown in the island, if any.
    /// A newer release, offered at the top of the session list.
    var update: AvailableUpdate?
    var isUpdating = false
    var updateError: String?
    /// Set by the controller: downloads and installs `update`.
    @ObservationIgnored var installUpdate: (() -> Void)?
    var onboarding: OnboardingStep?
    /// Installing the hooks is in progress.
    var isConnecting = false
    /// Why the last connect attempt failed.
    var onboardingError: String?

    /// The connect and jq screens stay open until answered, wherever the cursor goes.
    var isPinnedOpen: Bool { onboarding == .installJQ || onboarding == .connect }

    init(store: SessionStore) {
        self.store = store
    }

    enum Mode { case compact, peek, panel }

    static let coordinateSpace = "island"
    static let compactWidth: CGFloat = 300
    static let compactRadius: CGFloat = 14
    /// Bottom corner radius of the MacBook's hardware notch.
    static let notchCornerRadius: CGFloat = 8
    /// The compact rim's width; the island extends this far below the notch so the line shows.
    static let notchRimWidth: CGFloat = 2
    static let peekWidth: CGFloat = 400
    static let peekRowHeight: CGFloat = 38
    static let tallPeekBodyHeight: CGFloat = 60
    static let peekRadius: CGFloat = 26
    static let panelWidth: CGFloat = 440
    static let panelMaxHeight: CGFloat = 620
    static let panelRadius: CGFloat = 34
    /// Room around the island inside the window for its shadow.
    static let shadowPadding: CGFloat = 60

    var mode: Mode {
        if isExpanded { return .panel }
        return peek == nil ? .compact : .peek
    }

    var hasSessions: Bool { !store.sessions.isEmpty }

    /// The collapsed island shows beside the notch when there are sessions, or a lost connection.
    var showsBar: Bool { hasSessions || onboarding == .disconnected }

    /// With nothing to show the island hides inside the notch.
    var compactSize: CGSize {
        showsBar
            ? CGSize(width: max(Self.compactWidth, notchWidth + 88), height: notchHeight + Self.notchRimWidth)
            : CGSize(width: notchWidth, height: notchHeight)
    }

    var peekSize: CGSize {
        let body = peek?.isTall == true ? Self.tallPeekBodyHeight : Self.peekRowHeight + 4
        return CGSize(width: Self.peekWidth, height: notchHeight + body)
    }

    var panelSize: CGSize {
        let height = notchHeight + max(panelBodyHeight, 40)
        return CGSize(width: Self.panelWidth, height: min(height, Self.panelMaxHeight))
    }

    var currentSize: CGSize {
        switch mode {
        case .compact: compactSize
        case .peek: peekSize
        case .panel: panelSize
        }
    }

    var currentRadius: CGFloat {
        switch mode {
        case .compact: Self.compactRadius
        case .peek: Self.peekRadius
        case .panel: Self.panelRadius
        }
    }

    /// Fixed window size that fits the largest island plus its shadow.
    var windowSize: CGSize {
        CGSize(
            width: Self.panelWidth + Self.shadowPadding * 2,
            height: Self.panelMaxHeight + Self.shadowPadding
        )
    }

    /// How long a finished turn keeps the amethyst light before the island goes to sleep.
    static let finishedGlow: TimeInterval = 5 * 60

    /// Ticks every few seconds so time-based light (the finished glow) fades on schedule.
    var clock = Date()

    /// Light of the collapsed island and open panel, most urgent first: amber while someone
    /// waits, emerald while anyone works, amethyst for a few minutes after a finish, then dark.
    var stateGem: Gem {
        // Without hooks nothing else the island shows is current.
        if onboarding == .disconnected { return .ruby }
        if store.needsAttention { return .amber }
        if store.isAnyWorking { return .emerald }
        if store.sessions.values.contains(where: { s in
            // finishedAt survives the idle-prompt notification and is cleared by the next prompt.
            s.finishedAt.map { clock.timeIntervalSince($0) < Self.finishedGlow } ?? false
        }) { return .amethyst }
        return .obsidian
    }
}
