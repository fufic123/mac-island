import Foundation

/// The Claude subscription's usage limits, as Claude Code last reported them to its status line
/// (saved to ~/.mac-island/limits.json by island-statusline.sh).
public struct UsageLimits: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        /// Share of the window's allowance used, 0–100.
        public let usedPercent: Double
        public let resetsAt: Date

        public init(usedPercent: Double, resetsAt: Date) {
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
        }
    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    /// When Claude Code wrote these numbers.
    public let updatedAt: Date

    public static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".mac-island/limits.json")

    public init(fiveHour: Window?, sevenDay: Window?, updatedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
    }

    public static func decode(_ data: Data) -> UsageLimits? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any] else { return nil }
        func window(_ key: String) -> Window? {
            guard let raw = limits[key] as? [String: Any],
                  let used = (raw["used_percentage"] as? NSNumber)?.doubleValue,
                  let resets = (raw["resets_at"] as? NSNumber)?.doubleValue else { return nil }
            return Window(usedPercent: min(max(used, 0), 100), resetsAt: Date(timeIntervalSince1970: resets))
        }
        let updated = (root["updated_at"] as? NSNumber)?.doubleValue ?? 0
        let result = UsageLimits(fiveHour: window("five_hour"), sevenDay: window("seven_day"),
                                 updatedAt: Date(timeIntervalSince1970: updated))
        return result.fiveHour == nil && result.sevenDay == nil ? nil : result
    }

    public static func load(from url: URL = file) -> UsageLimits? {
        (try? Data(contentsOf: url)).flatMap(decode)
    }

    /// The numbers as they stand at `now`: a window whose reset time has passed starts over at 0%
    /// (Claude Code only writes while it runs, so the file can be older than the reset).
    public func current(at now: Date) -> UsageLimits {
        func fresh(_ window: Window?) -> Window? {
            guard let window else { return nil }
            return window.resetsAt > now ? window : Window(usedPercent: 0, resetsAt: window.resetsAt)
        }
        return UsageLimits(fiveHour: fresh(fiveHour), sevenDay: fresh(sevenDay), updatedAt: updatedAt)
    }
}
