import SwiftUI
import IslandCore

/// Three emerald bars for "running".
struct Equalizer: View {
    var color: Color = Crystal.emerald
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 2.5, height: 12)
                        .scaleEffect(x: 1, y: reduceMotion ? 0.7 : Self.scale(t + Double(i) * 0.33), anchor: .bottom)
                }
            }
            .frame(height: 12)
        }
    }

    /// 0.35 → 1 → 0.35 over one second, eased.
    private static func scale(_ t: Double) -> CGFloat {
        let p = t.truncatingRemainder(dividingBy: 1)
        return 0.35 + 0.65 * (1 - cos(2 * .pi * p)) / 2
    }
}

/// SF Symbol sized like the design's 15/17 pt glyphs.
struct Glyph: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 15
    var weight: Font.Weight = .semibold

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.86, weight: weight))
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }
}

/// Glyph for a session's status in rows.
struct StatusGlyph: View {
    let status: SessionStatus
    var size: CGFloat = 17

    var body: some View {
        switch status {
        case .needsPermission: Glyph(symbol: "lock", color: Crystal.amber, size: size)
        case .question: Glyph(symbol: "questionmark.bubble", color: Crystal.amber, size: size)
        case .working: Equalizer()
        case .done: Glyph(symbol: "checkmark", color: Crystal.amethyst, size: size, weight: .bold)
        case .waitingForInput, .idle: Glyph(symbol: "moon", color: Crystal.tertiary, size: size, weight: .medium)
        }
    }
}

/// Capsule button: flat fill, 38 pt.
struct CapsuleButton: View {
    let title: String
    let background: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Capsule().fill(background))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHand()
    }
}

extension View {
    /// Pointing-hand cursor while hovered, so clickable things read as clickable. Set on every
    /// move: the island is a non-activating panel and the cursor can be reset under it.
    func pointingHand(_ enabled: Bool = true) -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active: (enabled ? NSCursor.pointingHand : NSCursor.arrow).set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}
