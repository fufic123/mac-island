import AppKit
import IslandCore

MainActor.assumeIsolated {
    // README screenshots: MacIsland --render-screenshots <folder>
    if let i = CommandLine.arguments.firstIndex(of: "--render-screenshots"), i + 1 < CommandLine.arguments.count {
        _ = NSApplication.shared
        ScreenshotRenderer.run(into: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        exit(0)
    }
    // Only one island: if another copy is already running (say, one started at login and
    // one from /Applications), bring that one forward and quit this one.
    let me = ProcessInfo.processInfo.processIdentifier
    if let id = Bundle.main.bundleIdentifier,
       let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
           .first(where: { $0.processIdentifier != me }) {
        other.activate()
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // A regular app: shown running in the Dock, with an app menu.
    app.setActivationPolicy(.regular)
    app.run()
}
