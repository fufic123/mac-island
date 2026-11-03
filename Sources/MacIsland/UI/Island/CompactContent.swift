import SwiftUI
import IslandCore

/// Answers one question: "am I needed right now". Glyph on the left, session count on the right.
struct CompactContent: View {
    let model: IslandModel

    var body: some View {
        let gem = model.stateGem
        let height = model.compactSize.height
        let diameter = min(24, height - 8)
        // Same gap to the side as to the bottom, so the circles sit evenly in the corners.
        let margin = (height - diameter) / 2
        HStack {
            Bubble(gem: gem, diameter: diameter) { glyph(for: gem) }
                .overlay(alignment: .topTrailing) {
                    let agents = model.store.sessions.values.reduce(0) { $0 + $1.runningSubagents }
                    if agents > 0 {
                        // Running subagents across all sessions.
                        Text("\(agents)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 3.5)
                            .frame(minWidth: 13, minHeight: 13)
                            .background(Capsule().fill(Crystal.emerald))
                            .overlay(Capsule().strokeBorder(.black, lineWidth: 1.5))
                            .offset(x: 5, y: -3)
                    }
                }
            Spacer(minLength: 0)
            Bubble(gem: gem, diameter: diameter) {
                Text("\(model.store.sessions.count)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(gem == .obsidian ? Crystal.secondary : Crystal.text)
            }
        }
        .padding(.horizontal, margin)
        .frame(height: height)
    }

    @ViewBuilder
    private func glyph(for gem: Gem) -> some View {
        switch gem {
        case .amber:
            let question = model.store.sessions.values.contains { $0.status == .question }
                && !model.store.sessions.values.contains { $0.status == .needsPermission }
            Glyph(symbol: question ? "questionmark.bubble" : "lock", color: Crystal.amber, size: 13)
        case .emerald:
            Equalizer().scaleEffect(0.85)
        case .amethyst:
            Glyph(symbol: "sparkle", color: Crystal.amethyst, size: 13)
        case .ruby:
            Glyph(symbol: "exclamationmark.triangle", color: Crystal.ruby, size: 12)
        case .obsidian:
            Glyph(symbol: "moon", color: Crystal.tertiary, size: 13, weight: .medium)
        }
    }
}

/// Tinted circle holding a compact glyph or the session count.
struct Bubble<Content: View>: View {
    let gem: Gem
    let diameter: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let tint = gem == .obsidian ? Color.white : gem.color
        content
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(.black))
            .overlay(Circle().strokeBorder(tint.opacity(gem == .obsidian ? 0.1 : 0.28), lineWidth: 1))
    }
}
