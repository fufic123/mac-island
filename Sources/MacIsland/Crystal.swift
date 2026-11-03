import SwiftUI

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

    var highlight: Color {
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

/// Outline of the island the way the hardware notch is drawn: the top corners flare outward into
/// the menu bar, the sides drop straight, the bottom corners are rounded.
enum IslandOutline {
    /// Radius of the outward flare at the top corners.
    static let flare: CGFloat = 6

    /// `closed` gives the fill; open gives the rim (sides and bottom, no top edge).
    static func path(in rect: CGRect, radius: CGFloat, inset: CGFloat = 0, closed: Bool) -> Path {
        let f = flare
        let left = rect.minX + f + inset, right = rect.maxX - f - inset
        let top = rect.minY, bottom = rect.maxY - inset
        let r = max(0, min(radius - inset, (right - left) / 2, bottom - top - f))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: top))
        p.addQuadCurve(to: CGPoint(x: left, y: top + f), control: CGPoint(x: left, y: top))
        p.addLine(to: CGPoint(x: left, y: bottom - r))
        p.addArc(center: CGPoint(x: left + r, y: bottom - r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: right - r, y: bottom))
        p.addArc(center: CGPoint(x: right - r, y: bottom - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: right, y: top + f))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: top), control: CGPoint(x: right, y: top))
        if closed { p.closeSubpath() }
        return p
    }
}

/// Filled island silhouette.
struct IslandShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        IslandOutline.path(in: rect, radius: radius, closed: true)
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
        IslandOutline.path(in: rect, radius: radius, inset: inset, closed: false)
    }
}

/// Rim of a collapsed island or peek: comets of light running along the outline, from the left
/// flare down, across the bottom and up the right side, or a steady edge.
struct Rim: View {
    let gem: Gem
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineWidth: CGFloat { gem == .obsidian ? 1 : 2 }
    /// Comet length as a fraction of the outline.
    private static let tail: CGFloat = 0.32
    private static let segments = 10

    var body: some View {
        let shape = IslandRimShape(radius: radius, inset: lineWidth / 2)
        if gem.flows && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                // The head runs past the end by a tail's length, so each comet fully leaves before looping.
                let span = 1 + Self.tail
                let phase = CGFloat((t / gem.period).truncatingRemainder(dividingBy: 1))
                ZStack {
                    comet(shape, head: phase * span)
                    comet(shape, head: (phase + 0.5).truncatingRemainder(dividingBy: 1) * span)
                }
            }
        } else {
            shape.stroke(gem.color, lineWidth: lineWidth)
        }
    }

    private func comet(_ shape: IslandRimShape, head: CGFloat) -> some View {
        let n = Self.segments
        let piece = Self.tail / CGFloat(n)
        return ZStack {
            ForEach(0..<n, id: \.self) { k in
                let to = head - CGFloat(k) * piece
                let from = to - piece
                // Fades from the head back; slight overlap hides seams between pieces.
                let strength = pow(1 - Double(k) / Double(n), 1.6)
                shape.trim(from: max(0, min(1, from)), to: max(0, min(1, to + piece * 0.15)))
                    .stroke(gem.color.opacity(strength), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
            shape.trim(from: max(0, min(1, head - 0.02)), to: max(0, min(1, head)))
                .stroke(gem.highlight, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            shape.trim(from: max(0, min(1, head - 0.06)), to: max(0, min(1, head)))
                .stroke(gem.color.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: .round))
                .blur(radius: 2)
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
