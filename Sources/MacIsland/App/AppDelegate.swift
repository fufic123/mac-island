import AppKit
import IslandCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandController?
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        controller = IslandController()
        controller?.show()
        settings.onReconnect = { [weak self] in self?.controller?.offerConnect() }
        settings.onCheckForUpdates = { [weak self] in self?.controller?.checkForUpdate(manual: true) }
        LoginItem.register()
    }

    @objc private func checkForUpdates() {
        controller?.checkForUpdate(manual: true)
    }

    @objc private func openSettings() {
        settings.show()
    }

    /// The Dock icon's right-click menu.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
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
        let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        appMenu.addItem(update)
        appMenu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(prefs)
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
