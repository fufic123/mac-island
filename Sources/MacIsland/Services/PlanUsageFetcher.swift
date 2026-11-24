import Foundation
import IslandCore
import Security
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "limits")

/// The plan's usage limits straight from Anthropic, the way Claude Code's /usage gets them:
/// Claude Code's own sign-in token (from the login keychain) on a request to
/// api.anthropic.com/api/oauth/usage. Fresh every minute, whether you work in a terminal or in
/// Claude Desktop. The token never leaves the Mac except to Anthropic, and is never stored.
@MainActor
final class PlanUsageFetcher {
    private(set) var latest: UsageLimits?
    private var timer: Timer?
    private var token: String?
    /// The keychain prompt was declined: don't ask again until the app restarts.
    private var keychainDenied = false
    private var pausedUntil = Date.distantPast
    private var inFlight = false

    private static let interval: TimeInterval = 60
    private nonisolated static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private var onUpdate: (@MainActor () -> Void)?

    func start(onUpdate: @escaping @MainActor () -> Void) {
        self.onUpdate = onUpdate
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard Preferences.shared.limitsFromAccount, Preferences.shared.showLimits, let onUpdate else { return }
        fetch(onUpdate: onUpdate)
    }

    private func fetch(onUpdate: @escaping @MainActor () -> Void) {
        guard !inFlight, !keychainDenied, Date() >= pausedUntil else { return }
        inFlight = true
        let cached = token
        Task {
            defer { inFlight = false }
            // Read once and keep in memory; read again only when Anthropic turns the token down
            // (Claude Code refreshes it in the keychain).
            var current = cached
            if current == nil {
                switch await Task.detached(operation: { Self.readToken() }).value {
                case .token(let value): current = value
                case .denied:
                    keychainDenied = true
                    log.info("keychain access declined; limits come from the status line only")
                    return
                case .missing:
                    log.info("no Claude Code sign-in in the keychain")
                    return
                }
            }
            guard let current else { return }
            token = current
            switch await Self.request(token: current) {
            case .limits(let limits):
                log.info("limits: 5h \(limits.fiveHour?.usedPercent ?? -1, privacy: .public)% week \(limits.sevenDay?.usedPercent ?? -1, privacy: .public)%")
                latest = limits
                onUpdate()
            case .unauthorized:
                // Expired: Claude Code will have refreshed it; read it again next time.
                token = nil
            case .busy:
                pausedUntil = Date().addingTimeInterval(5 * 60)
            case .failed:
                break
            }
        }
    }

    private enum TokenResult: Sendable { case token(String), denied, missing }

    /// Claude Code's sign-in: `{"claudeAiOauth": {"accessToken": …, "expiresAt": ms, …}}`.
    private nonisolated static func readToken() -> TokenResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: break
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed: return .denied
        default: return .missing
        }
        guard let data = item as? Data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return .missing }
        return .token(token)
    }

    private enum RequestResult: Sendable { case limits(UsageLimits), unauthorized, busy, failed }

    private nonisolated static func request(token: String) async -> RequestResult {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MacIsland", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                guard let limits = UsageLimits.decodeUsageResponse(data, receivedAt: Date()) else {
                    log.error("usage answer had no limits")
                    return .failed
                }
                return .limits(limits)
            case 401, 403: return .unauthorized
            case 429: return .busy
            default:
                log.error("usage request failed: HTTP \(status, privacy: .public)")
                return .failed
            }
        } catch {
            return .failed
        }
    }
}
