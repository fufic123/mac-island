import AppKit
import SwiftUI

/// Owns the panel, keeps it pinned over the notch, expands it on hover and peeks on events.
@MainActor
final class IslandController {
    private let store = SessionStore()
    private let model: IslandModel
    private var pruneTimer: Timer?
    private var panel: IslandPanel?
    private var hosting: NSView?
    private var geometry: NotchGeometry?
    private var monitors: [Any] = []
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var hookServer: HookServer?
    private var hoverTracker: HoverTracker?
    private var stickySpace: StickySpace?

    /// Extra slack around the collapsed island so it's easy to hit with the cursor.
    private let hoverSlop: CGFloat = 8
    /// Brief dwell before expanding, so passing through the menu bar doesn't open it.
    private let expandDelay: TimeInterval = 0.12
    private let collapseDelay: TimeInterval = 0.15

    init() {
        model = IslandModel(store: store)
    }

    func show() {
        let panel = IslandPanel(contentRect: .zero)
        let store = store
        let hosting = IslandHostingView(rootView: IslandView(
            model: model,
            onFocus: { TerminalFocuser.focus($0) },
            onDecide: { store.decide(sessionId: $0, requestId: $1, decision: $2) },
            onReply: { [weak self] in self?.sendReply(sessionId: $0, text: $1) }
        ))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        hoverTracker = HoverTracker(view: hosting) { [weak self] in self?.updateHover() }
        store.onSignal = { [weak self] in self?.showPeek(Peek($0)) }

        layout()
        panel.orderFrontRegardless()
        let space = StickySpace()
        space.add(panel)
        stickySpace = space

        // Clicking elsewhere takes keyboard focus from the reply field; let the island close again.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.isComposing = false
                self?.updateHover()
            }
        }

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
        let server = HookServer { envelope, reply in
            Task { @MainActor in store.apply(envelope, reply: reply) }
        }
        let model = model
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated {
                store.prune()
                model.clock = .now
            }
        }
        do {
            try server.start()
            hookServer = server
        } catch {
            NSLog("MacIsland: failed to start hook server: \(error)")
        }
    }

    /// Sizes the window to fit the largest island and centers it on the notch.
    private func layout() {
        guard let panel, let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        self.geometry = geometry
        model.notchWidth = geometry.notchWidth
        model.notchHeight = geometry.notchHeight

        let size = model.windowSize
        let frame = NSRect(
            x: geometry.screenFrame.midX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }

    // MARK: Reply

    private func sendReply(sessionId: String, text: String) {
        store.reply(sessionId: sessionId, text: text)
        model.selectedSessionId = nil
        model.isComposing = false
        // Hand the keyboard back to whatever app was in front: a window that orders out loses key.
        if let panel, panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
            stickySpace?.add(panel)
        }
    }

    // MARK: Peek

    private func showPeek(_ peek: Peek) {
        peekWork?.cancel()
        model.peek = peek
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.peek?.id == peek.id else { return }
                self.model.peek = nil
            }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + peek.duration, execute: work)
    }

    // MARK: Hover

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
        let mouse = NSEvent.mouseLocation
        let inside = rect.contains(mouse)
        updatePointer(mouse, inside: inside)

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            guard !model.isExpanded, expandWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.expandWork = nil
                    // Still there after the dwell?
                    guard let rect = self.hoverRect(), rect.contains(NSEvent.mouseLocation) else { return }
                    self.peekWork?.cancel()
                    // Hovering a "Done" peek opens that session's last message and reply.
                    self.model.selectedSessionId = self.model.peek?.sessionId
                    self.model.peek = nil
                    self.model.isExpanded = true
                }
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + expandDelay, execute: work)
        } else {
            expandWork?.cancel()
            expandWork = nil
            // Stay open while typing a reply, even if the cursor wanders off.
            guard model.isExpanded, !model.isComposing, collapseWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.collapseWork = nil
                    guard !self.model.isComposing else { return }
                    self.model.isExpanded = false
                    self.model.selectedSessionId = nil
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
        }
    }

    /// Finds the row under the cursor (island view coordinates, top-left origin).
    /// Writes to the model only when it changes, so mouse moves don't re-render the island.
    private func updatePointer(_ mouse: NSPoint, inside: Bool) {
        var hovered: String?
        if inside, model.isExpanded, let panel, let hosting {
            let inWindow = panel.convertPoint(fromScreen: mouse)
            var point = hosting.convert(inWindow, from: nil)
            if !hosting.isFlipped { point.y = hosting.bounds.height - point.y }
            hovered = model.rowFrames.first { $0.value.contains(point) }?.key
        }
        if model.hoveredSessionId != hovered { model.hoveredSessionId = hovered }
    }
}
