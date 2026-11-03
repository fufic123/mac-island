import SwiftUI
import IslandCore

/// Measures the scrollable body so the island can size itself to it (up to 620 pt).
struct MeasuredScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical) {
            content.background(
                GeometryReader { geo in
                    Color.clear.preference(key: PanelBodyHeightKey.self, value: geo.size.height)
                }
            )
        }
        .scrollIndicators(.automatic)
    }
}
