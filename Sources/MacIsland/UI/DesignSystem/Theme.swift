import AppKit
import SwiftUI
import IslandCore

/// Which design the island draws. Mirrors `Preferences.design` (the screenshot renderer sets it
/// directly); tokens in `Crystal` and the glass pieces below read it. Only touched on the main
/// thread, where every view body runs.
enum Theme {
    nonisolated(unsafe) static var design: Design = .crystal

    static var isGlass: Bool { design == .liquidGlass }
}

// MARK: - Liquid color

/// Palettes for the slow liquid gradient, one per stone: the gem's hue plus neighbours it melts into.
enum Liquid {
    static func palette(_ gem: Gem) -> [Color] {
        switch gem {
        case .emerald: [Color(hex: 0x2FE39B), Color(hex: 0x19C6E6), Color(hex: 0x8CFFD2), Color(hex: 0x12A57E)]
        case .amber: [Color(hex: 0xFFB23E), Color(hex: 0xFF6F5E), Color(hex: 0xFFD978), Color(hex: 0xFF8F3A)]
        case .amethyst: [Color(hex: 0xB18CFF), Color(hex: 0x6F8DFF), Color(hex: 0xF29BFF), Color(hex: 0x8C5DFF)]
        case .ruby: [Color(hex: 0xFF3D6E), Color(hex: 0xFF8A5C), Color(hex: 0xFF62B0), Color(hex: 0xE0264F)]
        // Liquid metal: pearl and chrome with a hint of blue.
        case .obsidian: [Color(hex: 0xE9ECF5), Color(hex: 0x8E9AB8), Color(hex: 0xFFFFFF), Color(hex: 0x5D6884)]
        }
    }

    /// The palette for a button whose flat Crystal fill is `color`, or nil for neutral fills.
    static func palette(matching color: Color) -> [Color]? {
        switch color {
        case Crystal.emerald: palette(.emerald)
        case Crystal.amber: palette(.amber)
        case Crystal.amethyst: palette(.amethyst)
        case Crystal.ruby: palette(.ruby)
        case Crystal.text: palette(.obsidian)
        default: nil
        }
    }
}

/// A slow, animated gradient of four colours drifting into each other, like a shader gradient.
/// Redraws at most `fps` times a second and not at all while `paused` or with Reduce Motion.
struct LiquidGradient: View {
    let palette: [Color]
    var fps: Double = 20
    var paused = false
    /// Cycles per second of the drift; low is calm.
    var speed: Double = 0.12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / fps, paused: paused || reduceMotion)) { context in
            LiquidFrame(palette: palette, t: context.date.timeIntervalSinceReferenceDate * speed * 2 * .pi)
        }
    }
}

/// One frame of the liquid gradient: a 3 × 3 mesh with wandering inner points on macOS 15,
/// drifting linear and radial gradients before that.
struct LiquidFrame: View {
    let palette: [Color]
    let t: Double

    var body: some View {
        let c = palette.count >= 4 ? palette : palette + Array(repeating: palette.last ?? .white, count: 4 - palette.count)
        if #available(macOS 15, *) {
            let w = { (phase: Double, k: Double) -> Float in Float(0.5 + 0.28 * sin(t * k + phase)) }
            let e = { (phase: Double, k: Double) -> Float in Float(0.5 + 0.35 * sin(t * k + phase)) }
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [e(0, 1), 0], [1, 0],
                    [0, e(1.7, 0.8)], [w(0.4, 1.1), w(2.1, 0.9)], [1, e(3.1, 0.7)],
                    [0, 1], [e(4.2, 0.9), 1], [1, 1],
                ],
                colors: [c[0], c[1], c[2], c[3], c[2], c[0], c[1], c[0], c[3]],
                smoothsColors: true
            )
        } else {
            let angle = Angle(radians: t * 0.5)
            ZStack {
                LinearGradient(colors: [c[0], c[1]],
                               startPoint: UnitPoint(x: 0.5 + 0.5 * cos(angle.radians), y: 0.5 + 0.5 * sin(angle.radians)),
                               endPoint: UnitPoint(x: 0.5 - 0.5 * cos(angle.radians), y: 0.5 - 0.5 * sin(angle.radians)))
                RadialGradient(colors: [c[2], c[2].opacity(0)],
                               center: UnitPoint(x: 0.5 + 0.35 * sin(t * 0.9), y: 0.5 + 0.3 * cos(t * 0.7)),
                               startRadius: 0, endRadius: 140)
                RadialGradient(colors: [c[3].opacity(0.8), c[3].opacity(0)],
                               center: UnitPoint(x: 0.5 + 0.4 * cos(t * 0.6 + 2), y: 0.5 + 0.35 * sin(t * 0.8 + 1)),
                               startRadius: 0, endRadius: 120)
            }
        }
    }
}

// MARK: - Glass body

/// The renderer's stand-in for the desktop behind the island: offscreen there's no window server
/// to blur, so the glass blurs this view instead.
struct GlassBackdropKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: AnyView? = nil
}

extension EnvironmentValues {
    var glassBackdrop: AnyView? {
        get { self[GlassBackdropKey.self] }
        set { self[GlassBackdropKey.self] = newValue }
    }
}

/// Live blur of whatever is behind the island's window, with only the bottom corners rounded.
/// Animatable so the corners follow the island's morph.
private struct DesktopBlur: View, Animatable {
    var radius: CGFloat
    nonisolated var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    var body: some View {
        DesktopBlurView(radius: (radius * 2).rounded() / 2)
    }
}

private struct DesktopBlurView: NSViewRepresentable {
    let radius: CGFloat

    /// Purely decorative: clicks, scrolls and hovers go on to the SwiftUI content.
    final class PassThroughEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassThroughEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        // The island's app is rarely active; keep the blur on regardless.
        view.state = .active
        view.maskImage = Self.mask(radius: radius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        if view.maskImage?.capInsets.left != max(1, radius) {
            view.maskImage = Self.mask(radius: radius)
        }
    }

    /// Stretchable mask: square top, rounded bottom corners.
    private static func mask(radius: CGFloat) -> NSImage {
        let r = max(1, radius)
        let side = r * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            NSRect(x: 0, y: rect.midY, width: rect.width, height: rect.height / 2).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}

/// Liquid Glass island body for peek and panel: smoked glass over a blur of the desktop, black
/// where it covers the notch, with a slow wash of the state's colour rising from the bottom.
struct GlassBody: View {
    let radius: CGFloat
    let notchHeight: CGFloat
    let gem: Gem
    let animates: Bool
    @Environment(\.glassBackdrop) private var simulatedBackdrop

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        ZStack(alignment: .top) {
            if let simulatedBackdrop {
                GeometryReader { geo in
                    simulatedBackdrop
                        .frame(width: geo.size.width, alignment: .center)
                        .blur(radius: 28)
                        .saturation(1.5)
                }
                .clipped()
                // Rasterized, so the blur also shows in offscreen captures.
                .drawingGroup()
            } else {
                DesktopBlur(radius: radius)
            }
            // Smoke: keeps text legible over any wallpaper, light or busy.
            LinearGradient(colors: [.black.opacity(0.58), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            LiquidGradient(palette: Liquid.palette(gem), fps: 15, paused: !animates, speed: 0.06)
                .opacity(animates ? (gem == .obsidian ? 0.10 : 0.2) : 0)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .blendMode(.plusLighter)
            // Over the notch it must stay opaque black so it merges with the hardware.
            VStack(spacing: 0) {
                Color.black.frame(height: notchHeight)
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
                Spacer(minLength: 0)
            }
            // Soft inner glow along the glass's edge, as light caught in its thickness.
            // Collapsed, the body is only the notch and stays pure black.
            IslandRimShape(radius: radius, inset: 0)
                .stroke(.white.opacity(0.13), lineWidth: 10)
                .blur(radius: 7)
                .opacity(animates ? 1 : 0)
        }
        .clipShape(shape)
        .compositingGroup()
    }
}

/// Edge of the glass in peek and panel: a specular line brightest along the bottom, the state's
/// liquid colour beneath it.
struct GlassRim: View {
    let gem: Gem
    let radius: CGFloat
    let animates: Bool

    var body: some View {
        let (opacity, width) = gem.litBorder
        ZStack {
            if gem != .obsidian {
                LiquidGradient(palette: Liquid.palette(gem), fps: 20, paused: !animates)
                    .mask(IslandRimShape(radius: radius, inset: width / 2 + 0.5).stroke(lineWidth: width + 1))
                    .opacity(min(1, opacity + 0.35))
            }
            IslandRimShape(radius: radius, inset: 0.5)
                .stroke(LinearGradient(stops: [.init(color: .white.opacity(0.06), location: 0),
                                               .init(color: .white.opacity(0.22), location: 0.55),
                                               .init(color: .white.opacity(0.6), location: 1)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                .blendMode(.plusLighter)
        }
    }
}

/// Rim of the collapsed island or a peek in Liquid Glass: the state's liquid colour flowing
/// slowly through the line. Collapsed, it redraws only a few times a second.
struct LiquidRim: View {
    let gem: Gem
    let radius: CGFloat
    let fps: Double

    var body: some View {
        let lineWidth: CGFloat = gem == .obsidian ? 1 : 2
        let shape = IslandRimShape(radius: radius, inset: lineWidth / 2)
        if gem == .obsidian {
            shape.stroke(.white.opacity(0.2), lineWidth: lineWidth)
        } else {
            LiquidGradient(palette: Liquid.palette(gem), fps: fps, speed: 0.18)
                .mask(shape.stroke(lineWidth: lineWidth))
        }
    }
}

// MARK: - Glassy controls

extension View {
    /// Liquid Glass only: a specular edge, bright at the top and fading down, as on a glass bead.
    @ViewBuilder
    func glassEdge<S: InsettableShape>(_ shape: S, strength: Double = 1, visible: Bool = true) -> some View {
        if Theme.isGlass {
            overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.42 * strength), .white.opacity(0.05 * strength),
                                            .white.opacity(0.14 * strength)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(false)
            )
        } else {
            self
        }
    }
}

/// Capsule fill in Liquid Glass: accents become slow liquid colour, neutral fills frosted glass,
/// both with a sheen across the top half and a specular edge.
struct GlassCapsuleFill: View {
    let background: Color
    var animates = true

    var body: some View {
        ZStack {
            if let palette = Liquid.palette(matching: background) {
                LiquidGradient(palette: palette, fps: 20, paused: !animates, speed: 0.1)
            } else {
                Capsule().fill(background)
            }
            // Sheen: light caught across the top of the bead.
            LinearGradient(stops: [.init(color: .white.opacity(0.28), location: 0),
                                   .init(color: .white.opacity(0.06), location: 0.5),
                                   .init(color: .clear, location: 0.51)],
                           startPoint: .top, endPoint: .bottom)
            // Inner shadow at the bottom edge gives it thickness.
            Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 3).blur(radius: 3).offset(y: 1.5)
        }
        .clipShape(Capsule())
        .glassEdge(Capsule())
    }
}
