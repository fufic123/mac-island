import SwiftUI
import IslandCore

/// 400 × 74 announcement: glyph and label beside the notch, one line of news below.
struct PeekContent: View {
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
            // Inset past the body's margin: up here the island meets the menu bar with square
            // corners, and text close to that edge reads as cut off.
            .padding(.horizontal, 8)
            .padding(.top, 3)
            .frame(height: headerHeight)
            if peek.isTall {
                // Claude's closing line, up to two lines, like the design's "Update".
                message
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } else {
                HStack(spacing: 12) {
                    message
                        .font(.system(size: 15))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: IslandModel.peekRowHeight)
            }
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
        case .replied: Glyph(symbol: "arrow.up", color: Crystal.emerald, weight: .bold)
        case .denied: Glyph(symbol: "xmark", color: Crystal.secondary, size: 14, weight: .bold)
        }
    }

    private var label: String {
        switch peek.kind {
        case .permission: "Permission"
        case .question: "Question"
        case let .done(_, _, duration, _): duration.map { "Done · \(Clock.format($0))" } ?? "Done"
        case .replied: "Sent"
        case .allowed: "Allowed"
        case .denied: "Denied"
        case .ruleAdded: "Rule added"
        }
    }

    private var labelColor: Color {
        switch peek.kind {
        case .permission, .question: Crystal.amberText
        case .done: Crystal.amethystText
        case .allowed, .ruleAdded, .replied: Crystal.emerald
        case .denied: Crystal.secondary
        }
    }

    private var message: Text {
        switch peek.kind {
        case let .permission(project, phrase):
            Self.news(project, phrase)
        case let .question(project):
            Self.news(project, "asks a question")
        case let .done(_, project, duration, summary):
            if let summary {
                Text(project).fontWeight(.semibold) + Text(" \(summary)").foregroundStyle(Crystal.body)
            } else {
                Self.news(project, duration.map { "finished in \(Clock.format($0))" } ?? "finished")
            }
        case let .replied(project, text):
            Text(ToolDescriber.firstLine(text, limit: 40) ?? text).fontWeight(.semibold)
                + Text(" sent to \(project)").foregroundStyle(Crystal.secondary)
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
