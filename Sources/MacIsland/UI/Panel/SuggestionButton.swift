import SwiftUI
import IslandCore

/// Claude Code's suggested next prompt as its own button: one click sends it, Edit puts it in the field.
struct SuggestionButton: View {
    let text: String
    let onSend: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSend) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("Reply with suggestion")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.4)
                    }
                    .foregroundStyle(Crystal.amethystText)
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundStyle(Crystal.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 11)
                .padding(.leading, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Crystal.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit before sending")
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Crystal.amethyst.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Crystal.amethyst.opacity(0.35), lineWidth: 1))
    }
}
