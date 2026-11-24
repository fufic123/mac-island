import SwiftUI
import IslandCore
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "input")

/// Hosting view that takes the very first click: the island's app is never active,
/// and without this the first click on a button would only "activate" the panel.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The Liquid Glass blur is an AppKit view inside the SwiftUI tree, and the view SwiftUI wraps
    /// it in takes clicks for itself. Hand anything that lands on it to SwiftUI.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let hit, hit !== self, Self.isBlur(hit) { return self }
        return hit
    }

    private static func isBlur(_ view: NSView) -> Bool {
        view is NSVisualEffectView || view.subviews.contains { $0 is NSVisualEffectView }
    }

    override func mouseDown(with event: NSEvent) {
        log.info("mouseDown at \(event.locationInWindow.debugDescription, privacy: .public)")
        super.mouseDown(with: event)
    }
}
