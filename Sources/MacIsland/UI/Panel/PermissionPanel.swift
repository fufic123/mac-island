import SwiftUI
import IslandCore

/// The flow the island exists for: the question asked plainly, the whole command, Claude's
/// reason, two equal buttons and a quiet third option.
struct PermissionPanel: View {
    let session: AgentSession
    let queue: Int
    let now: Date
    let headerHeight: CGFloat
    let notchWidth: CGFloat
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
                .besideNotch(islandWidth: IslandModel.panelWidth, notchWidth: notchWidth,
                             edgeInset: 20, alignment: .leading)
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
