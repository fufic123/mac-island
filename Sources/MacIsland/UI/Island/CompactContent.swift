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
                Text("\(model.activeCount)")
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
            LayerEqualizer(scale: 0.85)
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
        if Theme.isGlass {
            // A glass bead: dark enough to read over a light menu bar, lit along its top edge.
            content
                .frame(width: diameter, height: diameter)
                .background {
                    ZStack {
                        Circle().fill(.black.opacity(0.78))
                        Circle().fill(RadialGradient(colors: [tint.opacity(gem == .obsidian ? 0.08 : 0.26), .clear],
                                                     center: .bottom, startRadius: 0, endRadius: diameter * 0.75))
                        Ellipse().fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)],
                                                      startPoint: .top, endPoint: .bottom))
                            .frame(width: diameter * 0.7, height: diameter * 0.42)
                            .offset(y: -diameter * 0.22)
                    }
                }
                .overlay(Circle().strokeBorder(tint.opacity(gem == .obsidian ? 0.12 : 0.4), lineWidth: 1))
                .glassEdge(Circle(), strength: 0.8)
        } else {
            content
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(.black))
                .overlay(Circle().strokeBorder(tint.opacity(gem == .obsidian ? 0.1 : 0.28), lineWidth: 1))
        }
    }
}
