import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu-bar-style agent: no Dock icon, no app menu.
    app.setActivationPolicy(.accessory)
    app.run()
}
