import AppKit
import SwiftUI

// The collapsed island is always on screen, so its endless animations (the rim's flowing light,
// the equalizer) run as Core Animation layer animations: the window server plays them, and the
// app does no work per frame. A SwiftUI timeline instead re-lays out the whole island every frame.

/// Set by the screenshot renderer: layer animations don't show in an offscreen capture, so
/// these views draw one still SwiftUI frame instead. (A key by hand: the @Entry macro needs a
/// plugin the Command Line Tools lack.)
private struct DrawsStaticallyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var drawsStatically: Bool {
        get { self[DrawsStaticallyKey.self] }
        set { self[DrawsStaticallyKey.self] = newValue }
    }
}

/// Frame rate for the layer animations: smooth, without running at the display's full 120 Hz.
@available(macOS 12.0, *)
private let layerFrameRate = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)

// MARK: - Flowing rim

/// The island's rim line with a gradient sliding along it, looping every `period` seconds.
/// `stops` span twice the rim's width and must repeat at the halfway point, so a shift of one
/// width loops seamlessly.
struct FlowingRim: View, Animatable {
    var radius: CGFloat
    let lineWidth: CGFloat
    let stops: [Gradient.Stop]
    let period: Double
    @Environment(\.drawsStatically) private var drawsStatically

    nonisolated var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    var body: some View {
        if drawsStatically {
            // One frame of the same gradient, as the SwiftUI timeline used to draw it.
            GeometryReader { geo in
                LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 2, height: geo.size.height)
                    .offset(x: -geo.size.width * 0.6)
            }
            .mask(IslandRimShape(radius: radius, inset: lineWidth / 2).stroke(lineWidth: lineWidth))
        } else {
            FlowingRimLayer(radius: radius, lineWidth: lineWidth, stops: stops, period: period)
                .allowsHitTesting(false)
        }
    }
}

private struct FlowingRimLayer: NSViewRepresentable {
    let radius: CGFloat
    let lineWidth: CGFloat
    let stops: [Gradient.Stop]
    let period: Double

    func makeNSView(context: Context) -> FlowingRimView { FlowingRimView() }

    func updateNSView(_ view: FlowingRimView, context: Context) {
        view.update(radius: radius, lineWidth: lineWidth,
                    colors: stops.map { NSColor($0.color).cgColor },
                    locations: stops.map { NSNumber(value: Double($0.location)) },
                    period: period)
    }
}

final class FlowingRimView: NSView {
    private let container = CALayer()
    private let gradient = CAGradientLayer()
    private let line = CAShapeLayer()
    private var radius: CGFloat = 0
    private var lineWidth: CGFloat = 2
    private var period: Double = 2.6
    /// Width and period the running animation was made for.
    private var animatedFor: (CGFloat, Double)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        layer = root
        wantsLayer = true
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        line.fillColor = nil
        line.strokeColor = NSColor.black.cgColor
        container.mask = line
        container.addSublayer(gradient)
        root.addSublayer(container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(radius: CGFloat, lineWidth: CGFloat, colors: [CGColor], locations: [NSNumber], period: Double) {
        self.radius = radius
        self.lineWidth = lineWidth
        self.period = period
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors
        gradient.locations = locations
        CATransaction.commit()
        relayout()
    }

    override func layout() {
        super.layout()
        relayout()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for layer in [layer, container, gradient, line] { layer?.contentsScale = scale }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Layer animations are dropped when a view leaves its window; start over on return.
        animatedFor = nil
        relayout()
    }

    private func relayout() {
        let bounds = self.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        line.frame = bounds
        line.lineWidth = lineWidth
        // Layers here are y-up like the window; the shape is drawn y-down, so flip it.
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        line.path = IslandRimShape(radius: radius, inset: lineWidth / 2).path(in: bounds).cgPath.copy(using: &flip)
        let width = bounds.width
        // Twice as wide as the rim; sliding it by one width brings the same picture back.
        gradient.bounds = CGRect(x: 0, y: 0, width: width * 2, height: bounds.height)
        gradient.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()

        guard window != nil, width > 0 else { return }
        if let (w, p) = animatedFor, w == width, p == period { return }
        animatedFor = (width, period)
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = 0
        slide.toValue = width
        slide.duration = period
        slide.repeatCount = .infinity
        slide.isRemovedOnCompletion = false
        // Same phase as a clock-driven loop, so a resize mid-flow doesn't make it jump back.
        slide.timeOffset = CACurrentMediaTime().truncatingRemainder(dividingBy: period)
        if #available(macOS 12.0, *) { slide.preferredFrameRateRange = layerFrameRate }
        gradient.add(slide, forKey: "flow")
    }
}

// MARK: - Equalizer

/// The three "running" bars, played by Core Animation. `scale` sizes them (layers ignore
/// SwiftUI's scaleEffect).
struct LayerEqualizer: View {
    var color: Color = Crystal.emerald
    var scale: CGFloat = 1
    @Environment(\.drawsStatically) private var drawsStatically
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if drawsStatically || reduceMotion {
            Equalizer(color: color).scaleEffect(scale)
        } else {
            EqualizerLayer(color: NSColor(color).cgColor, scale: scale)
                .frame(width: (2.5 * 3 + 2 * 2) * scale, height: 12 * scale)
                .allowsHitTesting(false)
        }
    }
}

private struct EqualizerLayer: NSViewRepresentable {
    let color: CGColor
    let scale: CGFloat

    func makeNSView(context: Context) -> EqualizerView { EqualizerView() }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.update(color: color, scale: scale)
    }
}

final class EqualizerView: NSView {
    private let bars = (0..<3).map { _ in CALayer() }
    private var scale: CGFloat = 1
    private var animating = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        layer = root
        wantsLayer = true
        for bar in bars {
            // Grows up from the bottom edge (layers here are y-up).
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            root.addSublayer(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(color: CGColor, scale: CGFloat) {
        self.scale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars { bar.backgroundColor = color }
        CATransaction.commit()
        relayout()
    }

    override func layout() {
        super.layout()
        relayout()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let s = window?.backingScaleFactor ?? 2
        layer?.contentsScale = s
        for bar in bars { bar.contentsScale = s }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        animating = false
        relayout()
    }

    private func relayout() {
        let width = 2.5 * scale, height = 12 * scale, gap = 2 * scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            bar.position = CGPoint(x: CGFloat(i) * (width + gap) + width / 2, y: 0)
            bar.cornerRadius = min(2 * scale, width / 2)
        }
        CATransaction.commit()

        guard window != nil, !animating else { return }
        animating = true
        let now = CACurrentMediaTime()
        for (i, bar) in bars.enumerated() {
            // 0.35 → 1 → 0.35 each second, eased, each bar a third of a beat behind the last.
            let pulse = CABasicAnimation(keyPath: "transform.scale.y")
            pulse.fromValue = 0.35
            pulse.toValue = 1
            pulse.duration = 0.5
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.isRemovedOnCompletion = false
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.timeOffset = (now + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
            if #available(macOS 12.0, *) { pulse.preferredFrameRateRange = layerFrameRate }
            bar.add(pulse, forKey: "pulse")
        }
    }
}
