import SwiftUI

/// First-run screens in the island (design: V6-Onboarding). No stone is lit yet, so the
/// primary button is neutral white rather than a state color.

/// "Connect Claude Code": what gets changed, in which file, and one button to do it.
struct ConnectPanel: View {
    let model: IslandModel
    let onAction: (OnboardingAction) -> Void

    private static let hooks: [(String, String)] = [
        ("SessionStart · SessionEnd", "a session opened or closed"),
        ("UserPromptSubmit · Stop", "a turn started or finished"),
        ("PreToolUse · PostToolUse", "what Claude is doing"),
        ("PermissionRequest", "Allow or Deny from the island"),
        ("Notification", "questions and idle prompts"),
        ("SubagentStart · SubagentStop", "subagents"),
    ]

    var body: some View {
        OnboardingFrame(model: model, symbol: "terminal", label: "Mac Island", tint: Crystal.secondary) {
            Text("Connect Claude Code")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.4)
            Text("Mac Island adds hooks to your Claude Code settings so sessions can report what they are doing. Nothing else changes.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Crystal.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Self.hooks, id: \.0) { hook, purpose in
                    (Text(hook) + Text("  \(purpose)").foregroundStyle(Crystal.tertiary))
                        .font(Crystal.mono(12))
                        .foregroundStyle(Crystal.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Crystal.codeBackground))
            .padding(.top, 14)
            Text("~/.claude/settings.json · a backup is kept next to it")
                .font(Crystal.mono(12))
                .foregroundStyle(Crystal.tertiary)
                .padding(.top, 10)
            ErrorLine(text: model.onboardingError)
            HStack(spacing: 10) {
                CapsuleButton(title: "Not now", background: Crystal.button, foreground: Crystal.text) { onAction(.notNow) }
                CapsuleButton(title: model.isConnecting ? "Connecting…" : "Connect",
                              background: Crystal.text, foreground: .black) { onAction(.connect) }
                    .disabled(model.isConnecting)
            }
            .padding(.top, 16)
        }
    }
}

/// Extra step when jq is missing: the hook installer and the hook itself need it.
struct InstallJQPanel: View {
    let model: IslandModel
    let onAction: (OnboardingAction) -> Void

    var body: some View {
        OnboardingFrame(model: model, symbol: "shippingbox", label: "Mac Island", tint: Crystal.secondary) {
            Text("One thing first: jq")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.4)
            Text("Mac Island talks to Claude Code through a small script that needs jq, a JSON tool. It's built into macOS 15 and later; on this Mac install it with Homebrew, then check again.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Crystal.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            HStack {
                Text(OnboardingDefaults.jqCommand)
                    .font(Crystal.mono(13))
                    .textSelection(.enabled)
                Spacer()
                Button { onAction(.copyJQCommand) } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Crystal.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy")
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Crystal.codeBackground))
            .padding(.top, 14)
            ErrorLine(text: model.onboardingError)
            HStack(spacing: 10) {
                CapsuleButton(title: "Not now", background: Crystal.button, foreground: Crystal.text) { onAction(.notNow) }
                CapsuleButton(title: "Check again", background: Crystal.text, foreground: .black) { onAction(.checkAgain) }
            }
            .padding(.top, 16)
        }
    }
}

/// The hooks were connected once and are gone: say so, and how to get them back.
struct DisconnectedPanel: View {
    let model: IslandModel
    let onAction: (OnboardingAction) -> Void

    var body: some View {
        OnboardingFrame(model: model, symbol: "exclamationmark.triangle", label: "Disconnected", tint: Crystal.rubyText,
                        symbolTint: Crystal.ruby) {
            Text("Hooks are missing")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.4)
            Text("Your Claude Code settings changed and the Mac Island hooks are gone. Sessions keep running, but the island can no longer see them.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Crystal.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            ErrorLine(text: model.onboardingError)
            HStack(spacing: 10) {
                CapsuleButton(title: "Show settings file", background: Crystal.button, foreground: Crystal.text) { onAction(.showSettings) }
                CapsuleButton(title: model.isConnecting ? "Connecting…" : "Reconnect",
                              background: Crystal.text, foreground: .black) { onAction(.connect) }
                    .disabled(model.isConnecting)
            }
            .padding(.top, 16)
        }
    }
}

/// Header beside the notch, then the screen's body sized to its content.
private struct OnboardingFrame<Content: View>: View {
    let model: IslandModel
    let symbol: String
    let label: String
    let tint: Color
    var symbolTint: Color = Crystal.text
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Glyph(symbol: symbol, color: symbolTint)
                Spacer()
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .besideNotch(islandWidth: IslandModel.panelWidth, notchWidth: model.notchWidth,
                                 edgeInset: 20, alignment: .trailing)
            }
            .frame(height: model.notchHeight)
            .padding(.horizontal, 20)

            MeasuredScroll {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.top, 16)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

private struct ErrorLine: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Crystal.rubyText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }
}
