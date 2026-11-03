import AppKit

/// Physical notch metrics for a screen, in points.
struct NotchGeometry {
    let screenFrame: NSRect
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool

    /// Screens without a notch (external displays) get a fake one of typical size.
    static let fallbackSize = CGSize(width: 200, height: 32)

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
            notchHeight = topInset
            hasNotch = true
        } else {
            notchWidth = Self.fallbackSize.width
            notchHeight = Self.fallbackSize.height
            hasNotch = false
        }
    }

    /// Prefer the built-in display with a notch, fall back to the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}
