import SwiftUI

extension View {
    /// Keeps header text within the strip beside the notch. Up there the notch covers the
    /// screen, so anything that runs under it is simply not visible.
    func besideNotch(islandWidth: CGFloat, notchWidth: CGFloat, edgeInset: CGFloat,
                     alignment: Alignment) -> some View {
        let room = max(36, (islandWidth - notchWidth) / 2 - edgeInset - 8)
        return lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: room, alignment: alignment)
    }
}
