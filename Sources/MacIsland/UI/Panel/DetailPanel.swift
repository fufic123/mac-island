import SwiftUI
import IslandCore

/// One session up close: Claude's last message in full and a field to answer it from the island.
struct DetailPanel: View {
    let model: IslandModel
    let session: AgentSession
    let now: Date
    let onFocus: () -> Void
    let onReply: (String) -> Void

    // Draft lives in the model: @State is a macro whose plugin the Command Line Tools lack.
    @FocusState private var fieldFocused: Bool

    private var draft: Binding<String> {
        Binding(get: { model.replyDraft }, set: { model.replyDraft = $0 })
    }

    private var canSend: Bool { !model.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { model.selectedSessionId = nil } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Crystal.secondary)
                        StatusGlyph(status: session.status, size: 15)
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(labelColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                Spacer()
                Button(action: onFocus) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(model.hoversOpenButton ? Crystal.text : Crystal.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(model.hoversOpenButton ? Crystal.keyCap : Crystal.button))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityLabel("Open in \(hostName)")
                .onHover { model.hoversOpenButton = $0 }
                .padding(.trailing, 10)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(time)
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Crystal.secondary)
                    if let cost = session.cost, cost > 0 {
                        Text(Self.formatCost(cost))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Crystal.tertiary)
                            .help("What this conversation has cost so far at API prices")
                    }
                }
            }
            .frame(height: model.notchHeight)
            .padding(.horizontal, 20)

            // A tooltip wouldn't show: the island's app is never active.
            if model.hoversOpenButton {
                Text("Opens this chat in \(hostName). Clicking the title or Claude's message does the same.")
                    .font(.system(size: 12))
                    .foregroundStyle(Crystal.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .transition(.opacity)
            }

            MeasuredScroll {
                VStack(alignment: .leading, spacing: 0) {
                    // The title and Claude's message jump to the terminal like the button does.
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.projectName)
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(-0.4)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        Text(message)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .foregroundStyle(Crystal.body)
                            .fixedSize(horizontal: false, vertical: true)
                            // The message can echo untrusted content (web pages, files), so only web
                            // links open; file:// and app URL schemes are dropped.
                            .environment(\.openURL, OpenURLAction { url in
                                ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
                            })
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onFocus)
                    .pointingHand()

                    if isShortened {
                        Button("Show full reply") { model.showsFullMessage = true }
                            .buttonStyle(.plain)
                            .pointingHand()
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Crystal.amethystText)
                            .padding(.top, 8)
                    }

                    if session.canReply, let suggestion = session.suggestion {
                        SuggestionButton(text: suggestion, onSend: { onReply(suggestion) }) {
                            model.replyDraft = suggestion
                            fieldFocused = true
                        }
                        .padding(.top, 16)
                    }

                    if session.canReply {
                        // The system placeholder is near-black on this dark field, so draw our own.
                        TextField("", text: draft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(Crystal.text)
                            .background(alignment: .leading) {
                                if model.replyDraft.isEmpty {
                                    Text("Reply to Claude…")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Crystal.tertiary)
                                        .allowsHitTesting(false)
                                }
                            }
                            .lineLimit(1...5)
                            // No autocorrect or Writing Tools: their popovers can't draw in a panel
                            // whose app is never active and show up as an empty grey box.
                            .autocorrectionDisabled()
                            .modifier(NoWritingTools())
                            .focused($fieldFocused)
                            .onSubmit(send)
                            .onExitCommand {
                                fieldFocused = false
                                model.selectedSessionId = nil
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Crystal.codeBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(fieldFocused ? Crystal.amethyst.opacity(0.55) : .clear, lineWidth: 1.5)
                            )
                            .padding(.top, 16)
                    }

                    if session.canReply {
                        CapsuleButton(
                            title: "Send",
                            background: canSend ? Crystal.amethyst : Crystal.button,
                            foreground: canSend ? Color(hex: 0x170B33) : Crystal.tertiary,
                            action: send
                        )
                        .disabled(!canSend)
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onChange(of: fieldFocused) { _, focused in model.isComposing = focused }
        .onDisappear {
            model.isComposing = false
            model.hoversOpenButton = false
        }
    }

    /// Where the "open" button takes you.
    private var hostName: String {
        switch session.termProgram {
        case "claude-desktop": "Claude Desktop"
        case "vscode": "the editor"
        default: "the terminal"
        }
    }

    private func send() {
        guard canSend else { return }
        let text = model.replyDraft
        model.replyDraft = ""
        fieldFocused = false
        onReply(text)
    }

    /// Light Markdown (bold, code, links) as Claude wrote it.
    /// Words of Claude's message shown before "Show full reply".
    private static let previewWords = 15

    private var fullText: String { session.lastMessage ?? "No message from Claude yet." }

    private var isShortened: Bool {
        !model.showsFullMessage && Self.words(fullText).count > Self.previewWords
    }

    private static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: { $0.isWhitespace })
    }

    /// The first words on one line, then "…", until the full reply is asked for.
    private var shownText: String {
        guard isShortened else { return fullText }
        return Self.words(fullText).prefix(Self.previewWords).joined(separator: " ") + "…"
    }

    private var message: AttributedString {
        let text = shownText
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private var label: String {
        switch session.status {
        case .done: "Done"
        case .working: "Running"
        case .needsPermission: "Permission"
        case .question: "Question"
        case .waitingForInput, .idle: "Idle"
        }
    }

    private var labelColor: Color {
        switch session.status {
        case .done: Crystal.amethystText
        case .working: Crystal.emerald
        case .needsPermission, .question: Crystal.amberText
        case .waitingForInput, .idle: Crystal.secondary
        }
    }

    static func formatCost(_ usd: Double) -> String {
        usd < 0.01 ? "<$0.01" : String(format: usd < 100 ? "$%.2f" : "$%.0f", usd)
    }

    private var time: String {
        switch session.status {
        case .working: Clock.format(now.timeIntervalSince(session.turnStartedAt ?? session.startedAt))
        case .needsPermission, .question:
            Clock.format(now.timeIntervalSince(session.permissionRequestedAt ?? session.lastEventAt))
        case .done, .waitingForInput, .idle: Clock.format(session.stoppedTime)
        }
    }
}

private struct NoWritingTools: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.writingToolsBehavior(.disabled)
        } else {
            content
        }
    }
}
