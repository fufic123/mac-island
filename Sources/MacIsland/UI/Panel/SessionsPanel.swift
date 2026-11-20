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
        let all = model.store.sorted.sorted {
            $0.displayGroup != $1.displayGroup ? $0.displayGroup.rawValue < $1.displayGroup.rawValue : $0.lastEventAt > $1.lastEventAt
        }
        let mode = model.prefs.idleMode
        let quiet = all.filter(\.isQuiet)
        let showsQuiet = mode == .show || (mode == .collapse && model.showsIdle)
        let sessions = showsQuiet ? all : all.filter { !$0.isQuiet }
        VStack(spacing: 0) {
            HStack {
                Text("Claude Code").fontWeight(.semibold)
                Spacer()
                Text(headerCount(active: all.count - quiet.count, quiet: quiet.count, mode: mode))
                    .monospacedDigit()
            }
            .font(.system(size: 13))
            .foregroundStyle(Crystal.secondary)
            .padding(.horizontal, 22)
            .frame(height: model.notchHeight)

            MeasuredScroll {
                VStack(spacing: 0) {
                    if let update = model.update {
                        UpdateBanner(model: model, update: update)
                            .padding(.top, 8)
                    }
                    if all.isEmpty {
                        emptyState
                    } else if sessions.isEmpty {
                        quietState(count: quiet.count, mode: mode)
                    } else if sessions.count > Self.groupThreshold {
                        ForEach(SessionGroup.allCases, id: \.self) { group in
                            let rows = sessions.filter { $0.displayGroup == group }
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
                    if mode == .collapse, !quiet.isEmpty {
                        idleToggle(count: quiet.count)
                    }
                    if model.prefs.showLimits, let limits = model.limits {
                        LimitsFooter(limits: limits.current(at: now), now: now)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .overlay(alignment: .top) {
                                Rectangle().fill(Crystal.rowHover).frame(height: 1).padding(.horizontal, 12)
                            }
                            .padding(.top, 6)
                    }
                    if model.prefs.showCost, let today = model.store.todayCost, today > 0 {
                        HStack {
                            Text("Total today")
                            Spacer()
                            Text(DetailPanel.formatCost(today)).monospacedDigit()
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Crystal.tertiary)
                        .help("All Claude Code conversations today at API prices")
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Crystal.rowHover).frame(height: 1).padding(.horizontal, 12)
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
    }

    private func headerCount(active: Int, quiet: Int, mode: IdleMode) -> String {
        let total = active + quiet
        if mode == .show || quiet == 0 { return total == 1 ? "1 session" : "\(total) sessions" }
        return active == 1 ? "1 active" : "\(active) active"
    }

    /// Row id the idle toggle reports for hover highlighting, alongside the session rows.
    static let idleToggleId = "__idle-toggle"

    /// A full-width row under the list that opens or folds the quiet sessions; laid out like a
    /// session row so it reads as part of the list and is as easy to hit.
    private func idleToggle(count: Int) -> some View {
        let hovered = model.hoveredSessionId == Self.idleToggleId
        return HStack(spacing: 14) {
            Glyph(symbol: "moon.zzz", color: Crystal.tertiary, size: 15, weight: .medium)
                .frame(width: 18)
            Text(model.showsIdle ? "Hide idle sessions" : (count == 1 ? "1 idle session" : "\(count) idle sessions"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(hovered ? Crystal.text : Crystal.secondary)
            Spacer(minLength: 8)
            Image(systemName: model.showsIdle ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovered ? Crystal.secondary : Crystal.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hovered ? Crystal.rowHover : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Crystal.expand) { model.showsIdle.toggle() }
        }
        .pointingHand()
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RowFramesKey.self,
                    value: [Self.idleToggleId: geo.frame(in: .named(IslandModel.coordinateSpace))]
                )
            }
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Crystal.rowHover).frame(height: 1).padding(.horizontal, 12)
        }
        .padding(.top, 6)
    }

    /// Everything open is idle and idle sessions aren't listed.
    private func quietState(count: Int, mode: IdleMode) -> some View {
        VStack(spacing: 2) {
            Text("Nothing running")
                .font(.system(size: 15))
                .foregroundStyle(Crystal.secondary)
            if mode == .hide {
                Text(count == 1 ? "1 idle session hidden" : "\(count) idle sessions hidden")
                    .font(.system(size: 12))
                    .foregroundStyle(Crystal.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.top, 4)
    }

    private func row(_ session: AgentSession, height: CGFloat, radius: CGFloat) -> some View {
        SessionRow(
            session: session,
            now: now,
            height: height,
            radius: radius,
            isHovered: model.hoveredSessionId == session.id,
            showsCost: model.prefs.showCost,
            swipeOffset: model.swipeSessionId == session.id ? model.swipeOffset : 0,
            onFocus: {
                // A row left open on Remove: a click on it just closes it again.
                if model.swipeSessionId != nil {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.closeSwipe() }
                    return
                }
                // Sessions with something to read or answer open in detail; the rest jump to the terminal.
                if session.opensDetail {
                    model.selectedSessionId = session.id
                } else {
                    onFocus(session)
                }
            },
            onRemove: {
                withAnimation(Crystal.collapse) {
                    model.store.dismiss(sessionId: session.id)
                    model.closeSwipe()
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
