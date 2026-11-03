import Observation
import CoreGraphics

@MainActor
@Observable
final class IslandModel {
    var isExpanded = false
    var notchWidth: CGFloat = NotchGeometry.fallbackSize.width
    var notchHeight: CGFloat = NotchGeometry.fallbackSize.height
    /// Debug readout of hook traffic until the session model lands.
    var lastEvent: HookEnvelope?
    var eventCount = 0

    static let expandedSize = CGSize(width: 420, height: 180)
    /// Radius of the outward flares where the island meets the menu bar.
    static let topCornerRadius: CGFloat = 6
    static let collapsedBottomRadius: CGFloat = 10
    static let expandedBottomRadius: CGFloat = 24

    var collapsedSize: CGSize {
        CGSize(width: notchWidth + Self.topCornerRadius * 2, height: notchHeight)
    }

    var currentSize: CGSize {
        isExpanded ? Self.expandedSize : collapsedSize
    }
}
