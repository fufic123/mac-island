import AppKit
import IslandCore

/// Reports cursor movement over a view even while the app is inactive.
/// Needed because a non-activating accessory app doesn't reliably get mouseMoved
/// events for its own windows, and global monitors never see events aimed at us.
@MainActor
final class HoverTracker: NSResponder {
    private let onMove: () -> Void

    init(view: NSView, onMove: @escaping () -> Void) {
        self.onMove = onMove
        super.init()
        view.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseEntered(with event: NSEvent) { onMove() }
    override func mouseMoved(with event: NSEvent) { onMove() }
    override func mouseExited(with event: NSEvent) { onMove() }
}
