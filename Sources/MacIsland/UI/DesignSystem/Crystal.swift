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
