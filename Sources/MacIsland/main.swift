import AppKit
import IslandCore

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // A regular app: shown running in the Dock, with an app menu.
    app.setActivationPolicy(.regular)
    app.run()
}
