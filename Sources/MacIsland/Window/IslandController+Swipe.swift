import AppKit
import SwiftUI

/// One two-finger swipe on the trackpad, from touch-down to lift-off.
final class SwipeState {
    enum Axis { case horizontal, vertical }
    var sessionId: String?
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var axis: Axis?
    /// Where the row started: 0, or open on its Remove button.
    var base: CGFloat = 0

    func reset() {
        sessionId = nil
        dx = 0
        dy = 0
        axis = nil
        base = 0
    }
}

/// Two-finger swipe left on a session row removes it from the island, like a notification.
/// Scroll events reach the panel even though its app is never active, so a local monitor sees them.
extension IslandController {
    func startSwipeTracking() {
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            // NSEvent isn't Sendable; decide on the main actor from its values, return it out here.
            let phase = event.phase, momentum = event.momentumPhase, precise = event.hasPreciseScrollingDeltas
            let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let consume = MainActor.assumeIsolated {
                self?.handleScroll(phase: phase, momentum: momentum, precise: precise, dx: dx, dy: dy) ?? false
            }
            return consume ? nil : event
        }) {
            addMonitor(monitor)
        }
    }

    /// Returns true to swallow the event (it moved a row instead of scrolling the list).
    /// `dx` follows the fingers: negative is a swipe to the left.
    private func handleScroll(phase: NSEvent.Phase, momentum: NSEvent.Phase, precise: Bool, dx: CGFloat, dy: CGFloat) -> Bool {
        guard precise else { return false }
        let swipe = swipeState
        if phase == .began {
            swipe.reset()
            let onList = model.isExpanded && model.selectedSessionId == nil && model.store.pendingDecisions.isEmpty
            swipe.sessionId = onList ? model.hoveredSessionId : nil
            if let id = swipe.sessionId, model.swipeSessionId == id { swipe.base = model.swipeOffset }
            return false
        }
        // Momentum after a horizontal swipe would scroll the list; swallow it.
        if momentum != [] { return swipe.axis == .horizontal }
        guard let id = swipe.sessionId else { return false }

        if phase == .changed {
            swipe.dx += dx
            swipe.dy += dy
            if swipe.axis == nil, hypot(swipe.dx, swipe.dy) > 6 {
                swipe.axis = abs(swipe.dx) > abs(swipe.dy) * 1.5 ? .horizontal : .vertical
            }
            guard swipe.axis == .horizontal else { return false }
            if model.swipeSessionId != id {
                // Another row was left open; this swipe takes over.
                model.swipeOffset = 0
                swipe.base = 0
            }
            model.swipeSessionId = id
            // Left follows the fingers; past the closed position it only gives a little.
            let x = swipe.base + swipe.dx
            model.swipeOffset = x < 0 ? x : min(12, x * 0.2)
            return true
        }
        if phase == .ended || phase == .cancelled {
            defer { swipe.sessionId = nil }
            guard swipe.axis == .horizontal else { return false }
            finishSwipe(id: id)
            return true
        }
        return false
    }

    /// Long swipe: remove. Past half the button: stay open on Remove. Otherwise: close.
    private func finishSwipe(id: String) {
        let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)
        let offset = -model.swipeOffset
        if offset >= IslandModel.swipeRemoveDistance {
            withAnimation(.easeIn(duration: 0.16)) { model.swipeOffset = -(IslandModel.panelWidth + 40) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                guard let self else { return }
                withAnimation(Crystal.collapse) {
                    self.model.store.dismiss(sessionId: id)
                    self.model.closeSwipe()
                }
            }
        } else if offset >= IslandModel.swipeRevealWidth / 2 {
            withAnimation(spring) { model.swipeOffset = -IslandModel.swipeRevealWidth }
        } else {
            withAnimation(spring) { model.swipeOffset = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.model.swipeOffset == 0 else { return }
                self.model.swipeSessionId = nil
            }
        }
    }
}
