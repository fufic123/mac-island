import SwiftUI

struct IslandView: View {
    let model: IslandModel
    let onFocus: (AgentSession) -> Void
    let onDecide: (_ sessionId: String, _ requestId: UUID, _ allow: Bool) -> Void

    private var store: SessionStore { model.store }
    private var spring: Animation { .spring(response: 0.38, dampingFraction: 0.78) }

    var body: some View {
        let size = model.currentSize
        let shape = NotchShape(
            topRadius: IslandModel.topCornerRadius,
            bottomRadius: model.isExpanded ? IslandModel.expandedBottomRadius : IslandModel.collapsedBottomRadius
        )
        ZStack(alignment: .top) {
            if store.needsAttention && !model.isExpanded {
                AttentionGlow(shape: shape)
            }
            shape.fill(.black)

            if model.isExpanded {
                SessionList(sessions: store.sorted, onFocus: onFocus, onDecide: onDecide)
                    .frame(height: model.listHeight, alignment: .top)
                    .padding(.top, model.notchHeight + IslandModel.listTopPadding)
                    .padding(.horizontal, IslandModel.topCornerRadius + IslandModel.listHorizontalPadding)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if model.showsEars {
                CollapsedEars(store: store)
                    .frame(height: model.notchHeight)
                    .padding(.horizontal, IslandModel.topCornerRadius)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring, value: model.isExpanded)
        .animation(spring, value: store.sessions.count)
        .animation(spring, value: model.listHeight)
    }
}

/// Status dot on the left of the notch, session count on the right.
private struct CollapsedEars: View {
    let store: SessionStore

    var body: some View {
        HStack(spacing: 0) {
            // Sorted by priority, so the first session is the most urgent one.
            StatusIndicator(status: store.sorted.first?.status ?? .idle)
                .frame(width: IslandModel.earWidth)
            Spacer(minLength: 0)
            Text("\(store.sessions.count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: IslandModel.earWidth)
        }
    }
}

/// Pulsing orange halo behind the collapsed island while a session needs the user.
private struct AttentionGlow: View {
    let shape: NotchShape

    var body: some View {
        shape
            .fill(Color.orange)
            .blur(radius: 8)
            .phaseAnimator([0.25, 0.85]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
    }
}

private struct SessionList: View {
    let sessions: [AgentSession]
    let onFocus: (AgentSession) -> Void
    let onDecide: (_ sessionId: String, _ requestId: UUID, _ allow: Bool) -> Void

    var body: some View {
        // Re-render periodically so relative times stay fresh.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView(.vertical) {
                VStack(spacing: IslandModel.rowSpacing) {
                    if sessions.isEmpty {
                        Text("No agent sessions")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, minHeight: IslandModel.rowHeight)
                    }
                    ForEach(sessions) { session in
                        SessionRow(
                            session: session,
                            now: context.date,
                            onFocus: { onFocus(session) },
                            onDecide: { requestId, allow in onDecide(session.id, requestId, allow) }
                        )
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

/// One session as a separate card; clicking it jumps to the session's terminal.
private struct SessionRow: View {
    let session: AgentSession
    let now: Date
    let onFocus: () -> Void
    let onDecide: (_ requestId: UUID, _ allow: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary
            if session.awaitingDecision, let requestId = session.permissionRequestId {
                permissionControls(requestId: requestId)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: IslandModel.rowHeight(for: session))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(session.status.needsAttention ? 0.1 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(session.status.needsAttention ? Color.orange.opacity(0.5) : .white.opacity(0.08))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onFocus)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            StatusIndicator(status: session.status)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    if let branch = session.gitBranch {
                        Text(branch)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(session.status.needsAttention ? Color.orange : .white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(timeLabel)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    /// The whole command is always reachable (scrolls when long): never approve what you can't see.
    private func permissionControls(requestId: UUID) -> some View {
        HStack(spacing: 8) {
            ScrollView(.vertical) {
                Text(session.permissionPreview ?? session.pendingPermission ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.5)))
            IslandButton(title: "Deny", tint: .white.opacity(0.15)) { onDecide(requestId, false) }
            IslandButton(title: "Allow", tint: .orange) { onDecide(requestId, true) }
        }
    }

    private var detail: String {
        switch session.status {
        case .needsPermission: "Needs permission · \(session.pendingPermission ?? "tool")"
        case .waitingForInput: "Waiting for your input"
        case .working: session.activity ?? "Working"
        case .done: "Done"
        case .idle: "Ready"
        }
    }

    /// Active sessions show how long they've been running; settled ones how long ago they settled.
    private var timeLabel: String {
        switch session.status {
        case .working, .needsPermission:
            Self.format(now.timeIntervalSince(session.startedAt))
        case .done, .waitingForInput, .idle:
            Self.format(now.timeIntervalSince(session.finishedAt ?? session.lastEventAt)) + " ago"
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct IslandButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StatusIndicator: View {
    let status: SessionStatus

    var body: some View {
        switch status {
        case .needsPermission, .waitingForInput:
            PulsingDot(color: .orange)
        case .working:
            PulsingDot(color: .green)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
        case .idle:
            Circle().fill(.white.opacity(0.35)).frame(width: 7, height: 7)
        }
    }
}

private struct PulsingDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .phaseAnimator([false, true]) { dot, on in
                dot
                    .scaleEffect(on ? 1.15 : 0.85)
                    .opacity(on ? 1 : 0.55)
            } animation: { _ in
                .easeInOut(duration: 0.8)
            }
    }
}

/// Notch silhouette: concave flares at the top corners, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let t = topRadius
        let b = min(bottomRadius, (w - 2 * t) / 2, h - t)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: t, y: t), control: CGPoint(x: t, y: 0))
        p.addLine(to: CGPoint(x: t, y: h - b))
        p.addQuadCurve(to: CGPoint(x: t + b, y: h), control: CGPoint(x: t, y: h))
        p.addLine(to: CGPoint(x: w - t - b, y: h))
        p.addQuadCurve(to: CGPoint(x: w - t, y: h - b), control: CGPoint(x: w - t, y: h))
        p.addLine(to: CGPoint(x: w - t, y: t))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - t, y: 0))
        p.closeSubpath()
        return p
    }
}
