import SwiftUI
import IslandCore
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "input")

/// Hosting view that takes the very first click: the island's app is never active,
/// and without this the first click on a button would only "activate" the panel.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        log.info("mouseDown at \(event.locationInWindow.debugDescription, privacy: .public)")
        super.mouseDown(with: event)
    }
}
