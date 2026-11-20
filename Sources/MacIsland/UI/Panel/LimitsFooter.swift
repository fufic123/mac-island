import SwiftUI
import IslandCore

/// The plan's 5-hour and weekly limits: how much is used and when each starts over.
struct LimitsFooter: View {
    let limits: UsageLimits
    let now: Date

    var body: some View {
        VStack(spacing: 10) {
            if let window = limits.fiveHour { row("5-hour limit", window) }
            if let window = limits.sevenDay { row("Weekly limit", window) }
        }
        .help("Your Claude plan's usage, as Claude Code last reported it")
    }

    private func row(_ title: String, _ window: UsageLimits.Window) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Text(title).foregroundStyle(Crystal.secondary)
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(window.usedPercent >= 70 ? color(window.usedPercent) : Crystal.secondary)
                if let resets = resetText(window.resetsAt) {
                    Text("· \(resets)").monospacedDigit().foregroundStyle(Crystal.tertiary)
                }
            }
            .font(.system(size: 12))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Crystal.button)
                    Capsule()
                        .fill(color(window.usedPercent))
                        .frame(width: max(window.usedPercent > 0 ? 4 : 0, geo.size.width * window.usedPercent / 100))
                }
            }
            .frame(height: 4)
        }
    }

    /// Green while there's room, amber from 70%, red from 90%.
    private func color(_ percent: Double) -> Color {
        percent >= 90 ? Crystal.ruby : percent >= 70 ? Crystal.amber : Crystal.emerald
    }

    /// "resets in 2h 14m" within a day, else "resets Tue 14:00"; nothing once the time has passed.
    private func resetText(_ date: Date) -> String? {
        let left = date.timeIntervalSince(now)
        guard left > 0 else { return nil }
        if left < 86400 {
            let minutes = Int(left / 60)
            return minutes < 60 ? "resets in \(max(minutes, 1))m" : "resets in \(minutes / 60)h \(minutes % 60)m"
        }
        return "resets " + Self.dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE jj:mm")
        return formatter
    }()
}
