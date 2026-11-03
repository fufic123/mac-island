import SwiftUI

struct IslandView: View {
    let model: IslandModel
    let store: SessionStore

    var body: some View {
        let size = model.currentSize
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(
                    topRadius: IslandModel.topCornerRadius,
                    bottomRadius: model.isExpanded ? IslandModel.expandedBottomRadius : IslandModel.collapsedBottomRadius
                )
                .fill(.black)

                if model.isExpanded {
                    expandedContent
                        .padding(.top, model.notchHeight + 8)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .frame(width: size.width, height: size.height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: model.isExpanded)
    }

    // Plain readout of the session model; the real list UI comes in step 4.
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            let sessions = store.sorted
            if sessions.isEmpty {
                Text("No agent sessions yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions.prefix(4)) { s in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(statusLabel(s.status)) \(s.projectName)\(s.gitBranch.map { " · \($0)" } ?? "")")
                        .font(.system(size: 12, weight: .medium))
                    Text(s.pendingPermission ?? s.activity ?? "")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusLabel(_ status: SessionStatus) -> String {
        switch status {
        case .needsPermission: "🟠 Needs permission ·"
        case .waitingForInput: "🟠 Waiting ·"
        case .working: "🟢"
        case .done: "✅"
        case .idle: "⚪"
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
