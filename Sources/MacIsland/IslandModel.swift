import Observation
import CoreGraphics
import Foundation

/// A short-lived expansion announcing an event, without hovering.
struct Peek: Equatable {
    enum Kind: Equatable {
        case permission(project: String, phrase: String)
        case question(project: String)
        case done(project: String, duration: TimeInterval?)
        case allowed(project: String, detail: String)
        case denied
        case ruleAdded(rule: String, project: String)
    }

    let id = UUID()
    let kind: Kind

    init(_ signal: IslandSignal) {
        switch signal {
        case let .permission(project, phrase): kind = .permission(project: project, phrase: phrase)
        case let .question(project): kind = .question(project: project)
        case let .done(project, duration): kind = .done(project: project, duration: duration)
        case let .allowed(project, detail): kind = .allowed(project: project, detail: detail)
        case .denied: kind = .denied
        case let .ruleAdded(rule, project): kind = .ruleAdded(rule: rule, project: project)
        }
    }

    /// How long it stays out before folding back.
    var duration: TimeInterval {
        switch kind {
        case .permission, .question, .done: 6
        case .allowed, .denied: 1.2
        case .ruleAdded: 5
        }
    }

    var gem: Gem {
        switch kind {
        case .permission, .question: .amber
        case .done: .amethyst
        case .allowed, .ruleAdded: .emerald
        case .denied: .obsidian
        }
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

    init(store: SessionStore) {
        self.store = store
    }

    enum Mode { case compact, peek, panel }

    static let coordinateSpace = "island"
    static let compactWidth: CGFloat = 300
    static let compactRadius: CGFloat = 14
    static let peekWidth: CGFloat = 400
    static let peekRowHeight: CGFloat = 38
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

    /// With no sessions the island hides inside the notch.
    var compactSize: CGSize {
        hasSessions
            ? CGSize(width: max(Self.compactWidth, notchWidth + 88), height: notchHeight + 2)
            : CGSize(width: notchWidth, height: notchHeight)
    }

    var peekSize: CGSize {
        CGSize(width: Self.peekWidth, height: notchHeight + Self.peekRowHeight + 4)
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

    /// Light of the collapsed island and open panel: amber while someone waits, emerald while
    /// anyone works, otherwise dark.
    var stateGem: Gem {
        if store.needsAttention { return .amber }
        if store.isAnyWorking { return .emerald }
        return .obsidian
    }
}
