import AppKit
import IslandCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        controller = IslandController()
        controller?.show()
        LoginItem.register()
    }

    @objc private func connectClaude() {
        controller?.offerConnect()
    }

    /// Clicking the Dock icon has no window to bring back; the island is always on screen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    private func makeMainMenu() -> NSMenu {
        let name = "Mac Island"
        let appMenu = NSMenu(title: name)
        appMenu.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let connect = NSMenuItem(title: "Connect to Claude Code…", action: #selector(connectClaude), keyEquivalent: "")
        connect.target = self
        appMenu.addItem(connect)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }
}
