import SwiftUI

struct IslandView: View {
    let model: IslandModel
    let onFocus: (AgentSession) -> Void
    let onDecide: (_ sessionId: String, _ requestId: UUID, _ decision: PermissionDecision) -> Void

    var body: some View {
        let size = model.currentSize
        let radius = model.currentRadius
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .shadow(color: .black.opacity(model.mode == .compact ? 0 : 0.55), radius: model.mode == .panel ? 25 : 20, y: model.mode == .panel ? 22 : 16)
            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
            border(radius: radius)
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: IslandModel.coordinateSpace)
        .onPreferenceChange(RowFramesKey.self) { frames in
            MainActor.assumeIsolated { model.rowFrames = frames }
        }
        .onPreferenceChange(PanelBodyHeightKey.self) { height in
            MainActor.assumeIsolated { model.panelBodyHeight = height }
        }
        .animation(model.isExpanded ? Crystal.expand : Crystal.collapse, value: model.isExpanded)
        .animation(Crystal.expand, value: model.peek)
        .animation(Crystal.expand, value: model.panelBodyHeight)
        .animation(Crystal.expand, value: model.hasSessions)
        .foregroundStyle(Crystal.text)
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .compact:
            if model.hasSessions {
                CompactContent(model: model)
                    .transition(.opacity)
            }
        case .peek:
            if let peek = model.peek {
                PeekContent(peek: peek, headerHeight: model.notchHeight)
                    .transition(.opacity)
            }
        case .panel:
            PanelContent(model: model, onFocus: onFocus, onDecide: onDecide)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func border(radius: CGFloat) -> some View {
        switch model.mode {
        case .compact:
            if model.hasSessions { Rim(gem: model.stateGem, radius: radius) }
        case .peek:
            if let peek = model.peek { Rim(gem: peek.gem, radius: radius) }
        case .panel:
            LitBorder(gem: model.stateGem, radius: radius)
        }
    }
}

// MARK: - Compact

/// Answers one question: "am I needed right now". Glyph on the left, session count on the right.
private struct CompactContent: View {
    let model: IslandModel

    var body: some View {
        let gem = model.stateGem
        HStack {
            glyph(for: gem)
            Spacer(minLength: 0)
            Text("\(model.store.sessions.count)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(gem == .obsidian ? Crystal.secondary : Crystal.text)
        }
        .padding(.horizontal, 13)
        .frame(height: model.compactSize.height)
    }

    @ViewBuilder
    private func glyph(for gem: Gem) -> some View {
        switch gem {
        case .amber:
            let question = model.store.sessions.values.contains { $0.status == .question }
                && !model.store.sessions.values.contains { $0.status == .needsPermission }
            Glyph(symbol: question ? "questionmark.bubble" : "lock", color: Crystal.amber)
        case .emerald:
            Equalizer()
        case .amethyst:
            Glyph(symbol: "sparkle", color: Crystal.amethyst)
        case .obsidian:
            Glyph(symbol: "moon", color: Crystal.tertiary, weight: .medium)
        }
    }
}

// MARK: - Peek

/// 400 × 74 announcement: glyph and label beside the notch, one line of news below.
private struct PeekContent: View {
    let peek: Peek
    let headerHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                glyph
                Spacer(minLength: 0)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(labelColor)
            }
            .frame(height: headerHeight)
            HStack(spacing: 12) {
                message
                    .font(.system(size: 15))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: IslandModel.peekRowHeight)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var glyph: some View {
        switch peek.kind {
        case .permission: Glyph(symbol: "lock", color: Crystal.amber)
        case .question: Glyph(symbol: "questionmark.bubble", color: Crystal.amber)
        case .done: Glyph(symbol: "checkmark", color: Crystal.amethyst, weight: .bold)
        case .allowed, .ruleAdded: Glyph(symbol: "checkmark", color: Crystal.emerald, weight: .bold)
        case .denied: Glyph(symbol: "xmark", color: Crystal.secondary, size: 14, weight: .bold)
        }
    }

    private var label: String {
        switch peek.kind {
        case .permission: "Permission"
        case .question: "Question"
        case .done: "Done"
        case .allowed: "Allowed"
        case .denied: "Denied"
        case .ruleAdded: "Rule added"
        }
    }

    private var labelColor: Color {
        switch peek.kind {
        case .permission, .question: Crystal.amberText
        case .done: Crystal.amethystText
        case .allowed, .ruleAdded: Crystal.emerald
        case .denied: Crystal.secondary
        }
    }

    private var message: Text {
        switch peek.kind {
        case let .permission(project, phrase):
            Self.news(project, phrase)
        case let .question(project):
            Self.news(project, "asks a question")
        case let .done(project, duration):
            Self.news(project, duration.map { "finished in \(Clock.format($0))" } ?? "finished")
        case let .allowed(project, detail):
            Self.news(project, detail)
        case .denied:
            Text("Claude will look for another way").foregroundStyle(Crystal.secondary)
        case let .ruleAdded(rule, project):
            Text(rule).font(Crystal.mono(13.5)) + Text(" is allowed in \(project)").foregroundStyle(Crystal.secondary)
        }
    }

    /// "**project** what happened".
    private static func news(_ project: String, _ rest: String) -> Text {
        Text(project).fontWeight(.semibold) + Text(" \(rest)").foregroundStyle(Crystal.secondary)
    }
}

// MARK: - Panel

private struct PanelContent: View {
    let model: IslandModel
    let onFocus: (AgentSession) -> Void
    let onDecide: (_ sessionId: String, _ requestId: UUID, _ decision: PermissionDecision) -> Void

    var body: some View {
        let pending = model.store.pendingDecisions
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
            } else {
                SessionsPanel(model: model, now: context.date, onFocus: onFocus)
            }
        }
    }
}

/// Measures the scrollable body so the island can size itself to it (up to 620 pt).
private struct MeasuredScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical) {
            content.background(
                GeometryReader { geo in
                    Color.clear.preference(key: PanelBodyHeightKey.self, value: geo.size.height)
                }
            )
        }
        .scrollIndicators(.automatic)
    }
}

/// Who is doing what. Rows have no frames or plates; glyph and color carry the state.
private struct SessionsPanel: View {
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
            onFocus: { onFocus(session) }
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

private struct SessionRow: View {
    let session: AgentSession
    let now: Date
    let height: CGFloat
    let radius: CGFloat
    let isHovered: Bool
    let onFocus: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            StatusGlyph(status: session.status)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.projectName)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.15)
                Text(action)
                    .font(.system(size: 13))
                    .foregroundStyle(session.status.needsAttention ? Crystal.amberText : Crystal.secondary)
                    .truncationMode(.tail)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if isHovered {
                HStack(spacing: 6) {
                    Text("Open terminal").font(.system(size: 13))
                    Text("↩")
                        .font(.system(size: 12))
                        .foregroundStyle(Crystal.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Crystal.keyCap))
                }
            } else {
                Text(time)
                    .font(.system(size: 15).monospacedDigit())
                    .foregroundStyle(timeColor)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(isHovered ? Crystal.rowHover : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RowFramesKey.self,
                    value: [session.id: geo.frame(in: .named(IslandModel.coordinateSpace))]
                )
            }
        )
    }

    private var action: String {
        switch session.status {
        case .needsPermission: session.pendingPermission ?? "Needs permission"
        case .question: session.question.map { "Asks: \($0)" } ?? "Asks a question"
        case .working: session.activity ?? "Thinking…"
        case .done: "Finished \(Clock.ago(now.timeIntervalSince(session.finishedAt ?? session.lastEventAt)))"
        case .waitingForInput, .idle: "Waiting for your next prompt"
        }
    }

    /// Waiting time for blocked sessions, turn time while running, last turn once done.
    private var time: String {
        switch session.status {
        case .needsPermission, .question:
            Clock.format(now.timeIntervalSince(session.permissionRequestedAt ?? session.lastEventAt))
        case .working:
            Clock.format(now.timeIntervalSince(session.turnStartedAt ?? session.startedAt))
        case .done:
            Clock.format(session.lastTurnDuration ?? 0)
        case .waitingForInput, .idle:
            Clock.format(now.timeIntervalSince(session.startedAt))
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

/// The flow the island exists for: the question asked plainly, the whole command, Claude's
/// reason, two equal buttons and a quiet third option.
private struct PermissionPanel: View {
    let session: AgentSession
    let queue: Int
    let now: Date
    let headerHeight: CGFloat
    let onDecide: (PermissionDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 7) {
                    Glyph(symbol: "lock", color: Crystal.amber)
                    Text(queue > 1 ? "Permission · 1 of \(queue)" : "Permission")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Crystal.amberText)
                }
                Spacer()
                Text(Clock.format(now.timeIntervalSince(session.permissionRequestedAt ?? now)))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Crystal.amberText)
            }
            .frame(height: headerHeight)
            .padding(.horizontal, 20)

            MeasuredScroll {
                VStack(alignment: .leading, spacing: 0) {
                    Text(ToolDescriber.permissionTitle(tool: session.permissionTool, project: session.projectName))
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.4)
                        .lineSpacing(2)
                        .padding(.top, 16)

                    // The whole command, never truncated: nothing gets approved unseen.
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.permissionPreview ?? session.pendingPermission ?? "")
                            .font(Crystal.mono(13))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if let path = session.displayPath {
                            Text(path)
                                .font(Crystal.mono(12))
                                .foregroundStyle(Crystal.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Crystal.codeBackground))
                    .padding(.top, 14)

                    if let reason = session.permissionReason {
                        Text("Claude: \(reason)")
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .foregroundStyle(Crystal.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                            .padding(.top, 12)
                    }

                    HStack(spacing: 10) {
                        CapsuleButton(title: "Deny", background: Crystal.button, foreground: Crystal.text) { onDecide(.deny) }
                        CapsuleButton(title: "Allow", background: Crystal.amber, foreground: Color(hex: 0x1A1000)) { onDecide(.allow) }
                    }
                    .padding(.top, 18)

                    if let always = session.alwaysAllowLabel {
                        Button { onDecide(.alwaysAllow) } label: {
                            Text(always)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Crystal.amberText)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Preferences

struct RowFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct PanelBodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
