import SwiftUI

/// "A new version is out" at the top of the session list, with a one-click install.
struct UpdateBanner: View {
    let model: IslandModel
    let update: AvailableUpdate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Crystal.emerald)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mac Island \(update.version) is out")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Crystal.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(model.updateError == nil ? Crystal.secondary : Crystal.rubyText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.installUpdate?() } label: {
                Text(model.isUpdating ? "Updating…" : model.updateError == nil ? "Update" : "Retry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.isUpdating ? Crystal.tertiary : Color(hex: 0x00140B))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(model.isUpdating ? Crystal.button : Crystal.emerald))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointingHand(!model.isUpdating)
            .disabled(model.isUpdating)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Crystal.emerald.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Crystal.emerald.opacity(0.3), lineWidth: 1))
    }

    private var subtitle: String {
        if let error = model.updateError { return error }
        if model.isUpdating { return "Downloading; the island restarts by itself." }
        return "You have \(Updater.currentVersion). Updating keeps your settings and permissions."
    }
}
