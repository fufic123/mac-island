import Observation
import CoreGraphics

@MainActor
@Observable
final class IslandModel {
    let store: SessionStore
    var isExpanded = false
    var notchWidth: CGFloat = NotchGeometry.fallbackSize.width
    var notchHeight: CGFloat = NotchGeometry.fallbackSize.height

    init(store: SessionStore) {
        self.store = store
    }

    /// Radius of the outward flares where the island meets the menu bar.
    static let topCornerRadius: CGFloat = 6
    static let collapsedBottomRadius: CGFloat = 10
    static let expandedBottomRadius: CGFloat = 24
    /// Width of each side "ear" next to the notch in the collapsed state.
    static let earWidth: CGFloat = 36
    static let expandedWidth: CGFloat = 480
    static let rowHeight: CGFloat = 50
    /// Row with the command preview and Allow/Deny buttons.
    static let permissionRowHeight: CGFloat = 112
    static let rowSpacing: CGFloat = 6
    static let maxVisibleRows = 6
    static let listTopPadding: CGFloat = 6
    static let listBottomPadding: CGFloat = 12
    static let listHorizontalPadding: CGFloat = 12
    /// Room around the island inside the panel for the attention glow.
    static let glowPadding: CGFloat = 20

    /// Ears appear only when there is something to show; otherwise the island hides in the notch.
    var showsEars: Bool { !store.sessions.isEmpty }

    var collapsedSize: CGSize {
        let ears = showsEars ? Self.earWidth * 2 : 0
        return CGSize(width: notchWidth + Self.topCornerRadius * 2 + ears, height: notchHeight)
    }

    static func rowHeight(for session: AgentSession) -> CGFloat {
        session.awaitingDecision ? permissionRowHeight : rowHeight
    }

    /// Past this the list scrolls.
    static let maxListHeight = CGFloat(maxVisibleRows) * rowHeight + CGFloat(maxVisibleRows - 1) * rowSpacing

    var listHeight: CGFloat {
        let sessions = store.sessions.values
        guard !sessions.isEmpty else { return Self.rowHeight }
        let rows = sessions.reduce(0) { $0 + Self.rowHeight(for: $1) }
        return min(rows + CGFloat(sessions.count - 1) * Self.rowSpacing, Self.maxListHeight)
    }

    var expandedSize: CGSize {
        CGSize(width: Self.expandedWidth, height: expandedHeight(list: listHeight))
    }

    var currentSize: CGSize {
        isExpanded ? expandedSize : collapsedSize
    }

    /// Fixed panel size that fits the largest island plus its glow.
    var panelSize: CGSize {
        CGSize(
            width: Self.expandedWidth + Self.glowPadding * 2,
            height: expandedHeight(list: Self.maxListHeight) + Self.glowPadding
        )
    }

    private func expandedHeight(list: CGFloat) -> CGFloat {
        notchHeight + Self.listTopPadding + list + Self.listBottomPadding
    }
}
