import SwiftUI
import IslandCore

struct PanelContent: View {
    let model: IslandModel
    let onFocus: (AgentSession) -> Void
    let onDecide: (_ sessionId: String, _ requestId: UUID, _ decision: PermissionDecision) -> Void
    let onReply: (_ sessionId: String, _ text: String) -> Void

    var body: some View {
        let pending = model.store.pendingDecisions
        let selected = model.selectedSessionId.flatMap { model.store.sessions[$0] }
        // Refresh timers once a second.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let request = pending.first, let requestId = request.permissionRequestId {
                PermissionPanel(
                    session: request,
                    queue: pending.count,
                    now: context.date,
                    headerHeight: model.notchHeight,
                    onDecide: { onDecide(request.id, requestId, $0) }
                )
            } else if let selected {
                DetailPanel(
                    model: model,
                    session: selected,
                    now: context.date,
                    onFocus: { onFocus(selected) },
                    onReply: { onReply(selected.id, $0) }
                )
            } else {
                SessionsPanel(model: model, now: context.date, onFocus: onFocus)
            }
        }
    }
}
