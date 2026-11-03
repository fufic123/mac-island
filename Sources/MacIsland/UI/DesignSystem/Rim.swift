import SwiftUI
import IslandCore

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
