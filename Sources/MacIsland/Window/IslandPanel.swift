import AppKit
import IslandCore

/// Borderless transparent panel that floats above the menu bar on every Space.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        // Menu bar is .mainMenu (24); .statusBar (25) draws on top of it.
        level = .statusBar
        // As a regular (Dock) app it can be deactivated or hidden; the island must stay put.
        hidesOnDeactivate = false
        canHide = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        // When the cursor is over the island itself, events go to us, not the global monitor.
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
    }

    // Key-capable so controls get clicks reliably, but `becomesKeyOnlyIfNeeded` keeps it from
    // taking keyboard focus away from the terminal on a plain button click.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
