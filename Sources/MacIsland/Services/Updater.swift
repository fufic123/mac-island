import AppKit
import Security
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "update")

/// A newer release on GitHub.
struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let notes: String
    let zipURL: URL
}

/// Updates the app from the GitHub releases: finds a newer release, downloads its zip, checks
/// that the new app is signed by the same certificate as this one, then swaps it in and relaunches.
/// The swap runs in a small shell script after the app quits, so nothing is replaced while it runs.
enum Updater {
    static let latestRelease = URL(string: "https://api.github.com/repos/fufic123/mac-island/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The latest release if it is newer than this app, nil if not.
    static func check() async throws -> AvailableUpdate? {
        var request = URLRequest(url: latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacIsland/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("GitHub didn't answer.") }
        let release = try JSONDecoder().decode(Release.self, from: data)
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        guard isNewer(version, than: currentVersion),
              let zip = release.assets.first(where: { $0.name == "MacIsland.zip" }),
              zip.browserDownloadUrl.scheme == "https"
        else { return nil }
        return AvailableUpdate(version: version, notes: release.body ?? "", zipURL: zip.browserDownloadUrl)
    }

    /// Numeric comparison of dotted versions: 0.3.10 is newer than 0.3.9.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Downloads and verifies the update, then quits so the swap script can replace the app.
    /// Returns only on failure.
    static func install(_ update: AvailableUpdate) async throws {
        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw UpdateError("Can't write to \(target.deletingLastPathComponent().path).")
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MacIslandUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let (download, _) = try await URLSession.shared.download(from: update.zipURL)
        let zip = work.appendingPathComponent("MacIsland.zip")
        try FileManager.default.moveItem(at: download, to: zip)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let newApp = work.appendingPathComponent("MacIsland.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else { throw UpdateError("The download has no app in it.") }

        let version = Bundle(url: newApp)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard version == update.version else { throw UpdateError("The download is version \(version ?? "?"), not \(update.version).") }
        try verifySameSigner(newApp)

        // Waits for this process to quit, swaps the app in and starts it again.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$3.old"
        if mv "$3" "$3.old"; then
          if ditto "$2" "$3"; then rm -rf "$3.old"; else rm -rf "$3"; mv "$3.old" "$3"; fi
        fi
        xattr -dr com.apple.quarantine "$3" 2>/dev/null
        open "$3"
        rm -rf "$4"
        """
        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/bash")
        swap.arguments = ["-c", script, "swap", String(ProcessInfo.processInfo.processIdentifier),
                          newApp.path, target.path, work.path]
        try swap.run()
        log.info("Installing \(update.version, privacy: .public); quitting for the swap")
        await MainActor.run { NSApp.terminate(nil) }
    }

    /// The new app must be validly signed and meet this app's designated requirement (same bundle
    /// id and same signing certificate), so a tampered or foreign download is never installed.
    private static func verifySameSigner(_ app: URL) throws {
        var me: SecStaticCode?
        var requirement: SecRequirement?
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &me) == errSecSuccess, let me,
              SecCodeCopyDesignatedRequirement(me, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode
        else { throw UpdateError("Couldn't read the app's signature.") }
        let status = SecStaticCodeCheckValidity(newCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
        guard status == errSecSuccess else {
            throw UpdateError("The update isn't signed like this app (\(status)); not installing it.")
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError("\(tool) failed.") }
    }

    private struct Release: Decodable {
        let tagName: String
        let body: String?
        let assets: [Asset]
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", body, assets }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
        enum CodingKeys: String, CodingKey { case name, browserDownloadUrl = "browser_download_url" }
    }
}

struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
