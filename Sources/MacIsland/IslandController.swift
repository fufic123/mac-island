import AppKit
import SwiftUI

/// Owns the panel, keeps it pinned over the notch and expands it on hover.
@MainActor
final class IslandController {
    private let store = SessionStore()
    private let model: IslandModel
    private var pruneTimer: Timer?
    private var panel: IslandPanel?
    private var geometry: NotchGeometry?
    private var monitors: [Any] = []
    private var collapseWork: DispatchWorkItem?
    private var hookServer: HookServer?
    private var hoverTracker: HoverTracker?

    /// Extra slack around the collapsed notch so it's easy to hit with the cursor.
    private let hoverSlop: CGFloat = 8
    private let collapseDelay: TimeInterval = 0.15

    init() {
        model = IslandModel(store: store)
    }

    func show() {
        let panel = IslandPanel(contentRect: .zero)
        let hosting = NSHostingView(rootView: IslandView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        hoverTracker = HoverTracker(view: hosting) { [weak self] in self?.updateHover() }

        layout()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        startMouseTracking()
        startHookServer()
    }

    private func startHookServer() {
        let store = store
        let server = HookServer { envelope in
            Task { @MainActor in store.apply(envelope) }
        }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { store.prune() }
        }
        do {
            try server.start()
            hookServer = server
        } catch {
            NSLog("MacIsland: failed to start hook server: \(error)")
        }
    }

    /// Sizes the panel to fit the largest island and centers it on the notch.
    private func layout() {
        guard let panel, let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        self.geometry = geometry
        model.notchWidth = geometry.notchWidth
        model.notchHeight = geometry.notchHeight

        let size = model.panelSize
        let frame = NSRect(
            x: geometry.screenFrame.midX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }

    private func startMouseTracking() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Global monitor fires while other apps are frontmost (always, for us);
        // local one covers events delivered to our own panel.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateHover() }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Hover hit zone in screen coordinates for the current state.
    /// It always reaches past the top screen edge: a cursor pinned against the edge
    /// reports y == maxY, which a plain rect would treat as outside.
    private func hoverRect() -> NSRect? {
        guard let geometry else { return nil }
        let size = model.currentSize
        let slop = model.isExpanded ? 0 : hoverSlop
        let top = geometry.screenFrame.maxY + hoverSlop
        let bottom = geometry.screenFrame.maxY - size.height - slop
        return NSRect(
            x: geometry.screenFrame.midX - size.width / 2 - slop,
            y: bottom,
            width: size.width + slop * 2,
            height: top - bottom
        )
    }

    private func updateHover() {
        guard let rect = hoverRect() else { return }
        let inside = rect.contains(NSEvent.mouseLocation)

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !model.isExpanded { model.isExpanded = true }
        } else if model.isExpanded, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.model.isExpanded = false
                    self?.collapseWork = nil
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
        }
    }
}
