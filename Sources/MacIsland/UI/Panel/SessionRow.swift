import SwiftUI
import IslandCore

struct SessionRow: View {
    let session: AgentSession
    let now: Date
    let height: CGFloat
    let radius: CGFloat
    let isHovered: Bool
    /// How far the row is swiped left (0 or negative).
    var swipeOffset: CGFloat = 0
    let onFocus: () -> Void
    var onRemove: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainLine
            // Only the ones still working; finished subagents drop out of the list.
            let running = session.subagents.filter { $0.state == .running }
            if !running.isEmpty {
                SubagentList(subagents: running, now: now)
                    .padding(.leading, 12 + 18 + 14)
                    .padding(.trailing, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(isHovered ? Crystal.rowHover : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
        .pointingHand()
        .contextMenu {
            Button("Remove from Island", action: onRemove)
        }
        .offset(x: swipeOffset)
        // Revealed behind the row as it slides left.
        .background(alignment: .trailing) {
            if swipeOffset < 0 {
                let armed = -swipeOffset >= IslandModel.swipeRemoveDistance
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Remove")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(armed ? Crystal.rubyText : Crystal.tertiary)
                .padding(.trailing, 16)
                .opacity(min(1, -swipeOffset / 50))
                .animation(.easeOut(duration: 0.12), value: armed)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RowFramesKey.self,
                    value: [session.id: geo.frame(in: .named(IslandModel.coordinateSpace))]
                )
            }
        )
    }

    private var mainLine: some View {
        HStack(spacing: 14) {
            Group {
                if session.wasInterrupted {
                    Glyph(symbol: "stop.circle", color: Crystal.tertiary, size: 17, weight: .medium)
                } else {
                    StatusGlyph(status: session.status)
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.projectName)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.15)
                Text(action)
                    .font(.system(size: 13))
                    .foregroundStyle(actionColor)
                    .truncationMode(.tail)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if isHovered {
                HStack(spacing: 6) {
                    Text(session.canReply ? "Reply" : session.opensDetail ? "Details" : "Open terminal")
                        .font(.system(size: 13))
                    Text("↩")
                        .font(.system(size: 12))
                        .foregroundStyle(Crystal.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Crystal.keyCap))
                }
            } else {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(time)
                        .font(.system(size: 15).monospacedDigit())
                        .foregroundStyle(timeColor)
                    if let cost = session.cost, cost > 0 {
                        Text(DetailPanel.formatCost(cost))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(Crystal.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: height)
    }

    private var action: String {
        if session.wasInterrupted { return "Stopped by you" }
        return switch session.status {
        case .needsPermission: session.pendingPermission ?? "Needs permission"
        case .question: session.question.map { "Asks: \($0)" } ?? "Asks a question"
        case .working: session.activity ?? "Thinking…"
        case .done, .waitingForInput, .idle:
            // Claude's closing line stays in the row until the next action.
            ToolDescriber.summary(session.lastMessage)
                ?? (session.status == .done
                    ? "Finished \(Clock.ago(now.timeIntervalSince(session.finishedAt ?? session.lastEventAt)))"
                    : "Waiting for your next prompt")
        }
    }

    private var actionColor: Color {
        if session.status.needsAttention { return Crystal.amberText }
        if session.status == .done && session.lastMessage != nil { return Crystal.amethystText }
        return Crystal.secondary
    }

    /// Waiting time for blocked sessions, turn time while running, last turn once done.
    private var time: String {
        switch session.status {
        case .needsPermission, .question:
            Clock.format(now.timeIntervalSince(session.permissionRequestedAt ?? session.lastEventAt))
        case .working:
            Clock.format(now.timeIntervalSince(session.turnStartedAt ?? session.startedAt))
        case .done, .waitingForInput, .idle:
            // Nothing is running, so the clock stands still on the last turn's length.
            Clock.format(session.stoppedTime)
        }
    }

    private var timeColor: Color {
        switch session.status {
        case .needsPermission, .question: Crystal.amberText
        case .working: Crystal.text
        default: Crystal.secondary
        }
    }
}
