import SwiftUI
import IslandCore

/// "Crystal" design tokens: an obsidian island whose state lives only in the light on its rim.
enum Crystal {
    static let text = Color(hex: 0xF5F5F7)
    static let body = Color(hex: 0xD1D1D6)
    static let secondary = Color(hex: 0xA1A1A6)
    static let tertiary = Color(hex: 0x8E8E93)
    static let rowHover = Color(hex: 0x1C1C1E)
    static let codeBackground = Color(hex: 0x161618)
    static let button = Color(hex: 0x232326)
    static let keyCap = Color(hex: 0x2C2C2E)

    static let emerald = Color(hex: 0x2FE39B)
    static let amber = Color(hex: 0xFFB23E)
    static let amberText = Color(hex: 0xFFC46B)
    static let amethyst = Color(hex: 0xB18CFF)
    static let amethystText = Color(hex: 0xC9B0FF)

    /// Code, branches and diffs only (SF Mono).
    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }

    /// Expand spring and the faster, bounce-free collapse.
    static let expand = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let collapse = Animation.easeOut(duration: 0.24)
}

/// Each island state is a stone with its own light.
enum Gem: Equatable {
    /// Idle: no light, a faint white rim.
    case obsidian
    /// Running.
    case emerald
    /// Waiting for the user (permission or question).
    case amber
    /// Done and updates.
    case amethyst

    var color: Color {
        switch self {
        case .obsidian: .white.opacity(0.14)
        case .emerald: Crystal.emerald
        case .amber: Crystal.amber
        case .amethyst: Crystal.amethyst
        }
    }

    private var highlight: Color {
        switch self {
        case .obsidian: .white.opacity(0.14)
        case .emerald: Color(hex: 0xDCFFF0)
        case .amber: Color(hex: 0xFFF1D6)
        case .amethyst: Color(hex: 0xEFE7FF)
        }
    }

    /// One pass of light along the rim, seconds.
    var period: Double {
        switch self {
        case .emerald, .obsidian: 2.6
        case .amber: 1.5
        case .amethyst: 3.6
        }
    }

    var flows: Bool { self != .obsidian }

    /// Steady border of an open panel: (opacity, width).
    var litBorder: (Double, CGFloat) {
        switch self {
        case .obsidian: (0.14, 1)
        case .emerald: (0.4, 1)
        case .amber: (0.6, 1.5)
        case .amethyst: (0.55, 1.5)
        }
    }

    /// Two comets per gradient, which is twice the rim's width, so shifting by one width loops seamlessly.
    var rimStops: [Gradient.Stop] {
        let dimOpacity = self == .amber ? 0.42 : 0.3
        let midOpacity = self == .amber ? 0.75 : 0.65
        let dim = color.opacity(dimOpacity), mid = color.opacity(midOpacity)
        let comet: [(Color, CGFloat)] = [
            (dim, 0), (dim, 0.17), (mid, 0.29), (color, 0.38), (highlight, 0.42), (color, 0.445), (dim, 0.485),
        ]
        var stops: [Gradient.Stop] = []
        for base: CGFloat in [0, 0.5] {
            for (c, offset) in comet {
                stops.append(Gradient.Stop(color: c, location: base + offset))
            }
        }
        stops.append(Gradient.Stop(color: dim, location: 1))
        return stops
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Sides and bottom of the island; the top merges into the menu bar, so it has no edge.
struct IslandRimShape: Shape {
    var radius: CGFloat
    var inset: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: 0)
        let bottom = rect.maxY - inset
        let radius = max(0, min(radius - inset, r.width / 2, bottom - r.minY))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: rect.minY - inset))
        p.addLine(to: CGPoint(x: r.minX, y: bottom - radius))
        p.addArc(center: CGPoint(x: r.minX + radius, y: bottom - radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX - radius, y: bottom))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: bottom - radius), radius: radius,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: rect.minY - inset))
        return p
    }
}

/// Rim of a collapsed island or peek: light flowing left to right, or a steady edge.
struct Rim: View {
    let gem: Gem
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineWidth: CGFloat { gem == .obsidian ? 1 : 2 }

    var body: some View {
        let shape = IslandRimShape(radius: radius, inset: lineWidth / 2)
        if gem.flows && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (t / gem.period).truncatingRemainder(dividingBy: 1)
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(stops: gem.rimStops, startPoint: .leading, endPoint: .trailing)
                        .frame(width: w * 2, height: geo.size.height)
                        .offset(x: -w + phase * w)
                }
                .mask(shape.stroke(lineWidth: lineWidth))
            }
        } else {
            shape.stroke(gem.color, lineWidth: lineWidth)
        }
    }
}

/// Steady border of the open panel, read rather than watched.
struct LitBorder: View {
    let gem: Gem
    let radius: CGFloat

    var body: some View {
        let (opacity, width) = gem.litBorder
        let color = gem == .obsidian ? Color.white.opacity(opacity) : gem.color.opacity(opacity)
        IslandRimShape(radius: radius, inset: width / 2)
            .stroke(color, lineWidth: width)
    }
}

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
    }
}

enum Clock {
    /// 4:12, 1:05:10.
    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "just now", "2 min ago", "1 h ago".
    static func ago(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        return "\(minutes / 60) h ago"
    }
}
