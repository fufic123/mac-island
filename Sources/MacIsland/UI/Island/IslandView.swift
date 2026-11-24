import SwiftUI
import IslandCore

struct IslandView: View {
    let model: IslandModel
    let onFocus: (AgentSession) -> Void
    let onDecide: (_ sessionId: String, _ requestId: UUID, _ decision: PermissionDecision) -> Void
    let onReply: (_ sessionId: String, _ text: String) -> Void
    let onOnboarding: (OnboardingAction) -> Void

    var body: some View {
        let size = model.currentSize
        let radius = model.currentRadius
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        let shadowPad = IslandModel.shadowPadding
        ZStack(alignment: .top) {
            // Blurring a resizing shadow every frame is the heaviest part of the morph;
            // rasterize it on the GPU (padded so the blur isn't clipped).
            // In compact the black is only the notch, so the circles beside it float over the menu bar;
            // it grows into the island when it opens.
            let fillsNotch = model.mode == .compact
            let bodyRadius = fillsNotch ? IslandModel.notchCornerRadius : radius
            let bodyShape = UnevenRoundedRectangle(bottomLeadingRadius: bodyRadius, bottomTrailingRadius: bodyRadius,
                                                   style: .continuous)
            let bodyWidth = fillsNotch ? model.notchWidth : size.width
            let bodyHeight = fillsNotch ? model.notchHeight : size.height
            let shadowOpacity = model.mode == .compact ? 0 : (Theme.isGlass ? 0.4 : 0.55)
            ZStack {
                bodyShape
                    .fill(.black)
                    .shadow(color: .black.opacity(shadowOpacity), radius: model.mode == .panel ? 25 : 20, y: model.mode == .panel ? 22 : 16)
                if Theme.isGlass {
                    // Glass is see-through: keep only the shadow outside it.
                    bodyShape.fill(.black).blendMode(.destinationOut)
                }
            }
                .frame(width: bodyWidth, height: bodyHeight)
                .padding(shadowPad)
                .drawingGroup()
                .padding(-shadowPad)
            if Theme.isGlass {
                GlassBody(radius: bodyRadius, notchHeight: model.notchHeight, gem: model.mode == .peek ? (model.peek?.gem ?? model.stateGem) : model.stateGem,
                          animates: model.mode != .compact)
                    .frame(width: bodyWidth, height: bodyHeight)
            }
            // Content is laid out once at its final size and only revealed by the animating
            // silhouette, instead of being re-laid-out (scroll view and all) on every frame.
            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .transaction { $0.animation = nil }
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
            border(radius: radius)
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: IslandModel.coordinateSpace)
        .onPreferenceChange(RowFramesKey.self) { frames in
            MainActor.assumeIsolated { model.rowFrames = frames }
        }
        .onPreferenceChange(PanelBodyHeightKey.self) { height in
            MainActor.assumeIsolated { model.panelBodyHeight = height }
        }
        .animation(model.isExpanded ? Crystal.expand : Crystal.collapse, value: model.isExpanded)
        .animation(Crystal.expand, value: model.peek)
        .animation(Crystal.expand, value: model.panelBodyHeight)
        .animation(Crystal.expand, value: model.showsBar)
        .foregroundStyle(Crystal.text)
        // Rebuild everything when the design changes, so every token is read afresh.
        .id(model.prefs.design)
    }

    /// Carries its own animation, since the content's layout transaction is not animated.
    private static let fade = AnyTransition.opacity.animation(.easeOut(duration: 0.18))

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .compact:
            if model.showsBar {
                CompactContent(model: model)
                    .transition(Self.fade)
            }
        case .peek:
            if let peek = model.peek {
                PeekContent(peek: peek, headerHeight: model.notchHeight, notchWidth: model.notchWidth)
                    .transition(Self.fade)
            }
        case .panel:
            PanelContent(model: model, onFocus: onFocus, onDecide: onDecide, onReply: onReply,
                         onOnboarding: onOnboarding)
                .transition(Self.fade)
        }
    }

    /// One rim for every mode, so it morphs between tracing the notch (compact) and the island's
    /// edge (peek, panel) instead of jumping. The open panel shows its steady border over it.
    @ViewBuilder
    private func border(radius: CGFloat) -> some View {
        let gem: Gem? = switch model.mode {
        case .compact: model.showsBar ? model.stateGem : nil
        case .peek: model.peek?.gem
        case .panel: model.stateGem
        }
        let line = IslandModel.notchRimWidth
        let tracesNotch = model.mode == .compact
        let rimSize = tracesNotch
            ? CGSize(width: model.notchWidth + line * 2, height: model.notchHeight + line)
            : model.currentSize
        ZStack(alignment: .top) {
            if let gem {
                let rimRadius = tracesNotch ? IslandModel.notchCornerRadius + line : radius
                // Faint black halo under the line, so it stands out against any menu bar.
                IslandRimShape(radius: rimRadius, inset: line / 2)
                    .stroke(.black.opacity(0.55), lineWidth: line * 3.5)
                    .blur(radius: 2)
                    // Glass: only outside, since inside it would draw a dark ring on the glass.
                    .mask(OutsideMask(radius: rimRadius, inverted: Theme.isGlass && !tracesNotch).fill(style: FillStyle(eoFill: true)))
                    .frame(width: rimSize.width, height: rimSize.height)
                    .opacity(model.mode == .panel ? 0 : 1)
                    .transition(.opacity)
                Group {
                    if Theme.isGlass {
                        // Collapsed it's always on screen, so the liquid only drifts a few frames a second.
                        LiquidRim(gem: gem, radius: rimRadius, fps: tracesNotch ? 8 : 20)
                    } else {
                        Rim(gem: gem, radius: rimRadius)
                    }
                }
                    .frame(width: rimSize.width, height: rimSize.height)
                    .opacity(model.mode == .panel ? 0 : 1)
                    .transition(.opacity)
            }
            if Theme.isGlass {
                if model.mode != .compact {
                    GlassRim(gem: model.stateGem, radius: radius, animates: model.mode == .panel)
                        .opacity(model.mode == .panel ? 1 : 0)
                }
            } else {
                LitBorder(gem: model.stateGem, radius: radius)
                    .opacity(model.mode == .panel ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Everything around the island (and under it unless `inverted` is false, which masks nothing).
private struct OutsideMask: Shape {
    var radius: CGFloat
    var inverted: Bool

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect.insetBy(dx: -40, dy: -40))
        if inverted {
            p.addPath(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                .path(in: rect.insetBy(dx: 0, dy: -1).offsetBy(dx: 0, dy: -1)))
        }
        return p
    }
}
