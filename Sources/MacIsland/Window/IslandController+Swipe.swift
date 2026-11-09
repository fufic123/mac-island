import AppKit
import SwiftUI

/// One two-finger swipe on the trackpad, from touch-down to lift-off.
final class SwipeState {
    enum Axis { case horizontal, vertical }
    var sessionId: String?
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var axis: Axis?

    func reset() {
        sessionId = nil
        dx = 0
        dy = 0
        axis = nil
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
            model.swipeSessionId = id
            // Left follows the fingers; right only gives a little, like a rubber band.
            model.swipeOffset = swipe.dx < 0 ? swipe.dx : min(12, swipe.dx * 0.2)
            return true
        }
        if phase == .ended || phase == .cancelled {
            defer { swipe.sessionId = nil }
            guard swipe.axis == .horizontal else { return false }
            finishSwipe(remove: phase == .ended && model.swipeOffset <= -IslandModel.swipeRemoveDistance, id: id)
            return true
        }
        return false
    }

    private func finishSwipe(remove: Bool, id: String) {
        guard remove else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.swipeOffset = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.model.swipeOffset == 0 else { return }
                self.model.swipeSessionId = nil
            }
            return
        }
        withAnimation(.easeIn(duration: 0.16)) { model.swipeOffset = -(IslandModel.panelWidth + 40) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self else { return }
            withAnimation(Crystal.collapse) {
                self.model.store.dismiss(sessionId: id)
                self.model.swipeSessionId = nil
                self.model.swipeOffset = 0
            }
        }
    }
}
