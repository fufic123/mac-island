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
    static let earWidth: CGFloat = 32
    static let expandedWidth: CGFloat = 420
    static let rowHeight: CGFloat = 46
    static let maxVisibleRows = 6
    static let listTopPadding: CGFloat = 4
    static let listBottomPadding: CGFloat = 12
    /// Room around the island inside the panel for the attention glow.
    static let glowPadding: CGFloat = 20

    /// Ears appear only when there is something to show; otherwise the island hides in the notch.
    var showsEars: Bool { !store.sessions.isEmpty }

    var collapsedSize: CGSize {
        let ears = showsEars ? Self.earWidth * 2 : 0
        return CGSize(width: notchWidth + Self.topCornerRadius * 2 + ears, height: notchHeight)
    }

    var visibleRows: Int { min(max(store.sessions.count, 1), Self.maxVisibleRows) }

    var expandedSize: CGSize {
        CGSize(width: Self.expandedWidth, height: expandedHeight(rows: visibleRows))
    }

    var currentSize: CGSize {
        isExpanded ? expandedSize : collapsedSize
    }

    /// Fixed panel size that fits the largest island plus its glow.
    var panelSize: CGSize {
        CGSize(
            width: Self.expandedWidth + Self.glowPadding * 2,
            height: expandedHeight(rows: Self.maxVisibleRows) + Self.glowPadding
        )
    }

    private func expandedHeight(rows: Int) -> CGFloat {
        notchHeight + Self.listTopPadding + CGFloat(rows) * Self.rowHeight + Self.listBottomPadding
    }
}
