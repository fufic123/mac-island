import SwiftUI
import IslandCore

/// Who is doing what. Rows have no frames or plates; glyph and color carry the state.
struct SessionsPanel: View {
    let model: IslandModel
    let now: Date
    let onFocus: (AgentSession) -> Void

    /// Past this many sessions the list splits into groups.
    private static let groupThreshold = 4

    var body: some View {
        let sessions = model.store.sorted
        VStack(spacing: 0) {
            HStack {
                Text("Claude Code").fontWeight(.semibold)
                Spacer()
                Text(sessions.count == 1 ? "1 session" : "\(sessions.count) sessions")
                    .monospacedDigit()
            }
            .font(.system(size: 13))
            .foregroundStyle(Crystal.secondary)
            .padding(.horizontal, 22)
            .frame(height: model.notchHeight)

            MeasuredScroll {
                VStack(spacing: 0) {
                    if sessions.isEmpty {
                        emptyState
                    } else if sessions.count > Self.groupThreshold {
                        ForEach(SessionGroup.allCases, id: \.self) { group in
                            let rows = sessions.filter { $0.status.group == group }
                            if !rows.isEmpty {
                                Text(group.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(color(for: group))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 14)
                                    .padding(.bottom, 4)
                                ForEach(rows) { row($0, height: 52, radius: 14) }
                            }
                        }
                    } else {
                        ForEach(sessions) { row($0, height: 56, radius: 16) }
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
    }

    private func row(_ session: AgentSession, height: CGFloat, radius: CGFloat) -> some View {
        SessionRow(
            session: session,
            now: now,
            height: height,
            radius: radius,
            isHovered: model.hoveredSessionId == session.id,
            onFocus: {
                // Sessions with something to read or answer open in detail; the rest jump to the terminal.
                if session.opensDetail {
                    model.selectedSessionId = session.id
                } else {
                    onFocus(session)
                }
            }
        )
    }

    private var emptyState: some View {
        (Text("Run ") + Text("claude").font(Crystal.mono(13.5)).foregroundStyle(Crystal.text) + Text(" in any terminal to begin"))
            .font(.system(size: 15))
            .foregroundStyle(Crystal.secondary)
            .frame(maxWidth: .infinity, minHeight: 56)
    }

    private func color(for group: SessionGroup) -> Color {
        switch group {
        case .needsYou: Crystal.amberText
        case .running: Crystal.emerald
        case .finished: Crystal.amethystText
        case .idle: Crystal.secondary
        }
    }
}
