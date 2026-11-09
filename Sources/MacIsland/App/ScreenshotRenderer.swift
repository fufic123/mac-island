import AppKit
import IslandCore
import SwiftUI

/// Renders the island's screens with demo sessions to PNGs for the README:
/// `MacIsland --render-screenshots <folder>`. Draws offscreen, so it needs no screen-recording
/// permission and never touches real sessions or hooks.
@MainActor
enum ScreenshotRenderer {
    static func run(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for shot in shots() {
            let url = folder.appendingPathComponent("\(shot.name).png")
            if let png = render(shot.model) {
                try? png.write(to: url)
                print("wrote \(url.path)")
            }
        }
    }

    private struct Shot {
        let name: String
        let model: IslandModel
    }

    private static let now = Date()

    private static func shots() -> [Shot] {
        var shots: [Shot] = []

        let list = demoStore()
        shots.append(Shot(name: "feature-sessions", model: expanded(list)))

        let permission = demoStore()
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        let responder = PermissionResponder(connection: HookConnection(fd: fds[0]), suggestions: [[
            "type": "addRules", "behavior": "allow", "destination": "localSettings",
            "rules": [["toolName": "Bash", "ruleContent": "npm run migrate:*"]],
        ]])
        apply(permission, "api", ["hook_event_name": "PermissionRequest", "tool_name": "Bash",
                                  "tool_input": ["command": "npm run migrate -- --env staging",
                                                 "description": "Run the database migrations on staging"]],
              ago: 6, reply: .permission(responder))
        shots.append(Shot(name: "feature-permission", model: expanded(permission)))

        let reply = demoStore()
        waitForReply(reply, "docs")
        shots.append(Shot(name: "feature-reply", model: expanded(reply, selected: "docs")))

        let queued = demoStore()
        queued.reply(sessionId: "web", text: "Also run the e2e tests before you open the PR")
        shots.append(Shot(name: "feature-queued", model: expanded(queued, selected: "web")))

        let swipe = demoStore()
        let swipeModel = expanded(swipe)
        swipeModel.swipeSessionId = "docs"
        swipeModel.swipeOffset = -IslandModel.swipeRevealWidth
        shots.append(Shot(name: "feature-swipe", model: swipeModel))

        let update = demoStore()
        let updateModel = expanded(update)
        updateModel.update = AvailableUpdate(version: "0.4.0", notes: "", zipURL: URL(string: "https://example.com")!)
        shots.append(Shot(name: "feature-update", model: updateModel))

        let open = demoStore()
        waitForReply(open, "docs")
        let openModel = expanded(open, selected: "docs")
        openModel.hoversOpenButton = true
        openModel.showsOpenHint = true
        shots.append(Shot(name: "feature-open", model: openModel))

        let done = demoStore()
        let doneModel = IslandModel(store: done)
        doneModel.peek = Peek(.done(sessionId: "docs", project: "docs", duration: 222,
                                    summary: "Rewrote the install guide and fixed 4 broken links."))
        shots.append(Shot(name: "feature-done", model: doneModel))

        return shots
    }

    /// Three sessions: one working with two subagents, one finished, one idle.
    private static func demoStore() -> SessionStore {
        let store = SessionStore()
        apply(store, "web", ["hook_event_name": "UserPromptSubmit", "prompt": "Plan dark mode"], ago: 1500)
        apply(store, "web", ["hook_event_name": "Stop",
                             "last_assistant_message": "Plan ready: swap the color tokens for semantic ones, then update the snapshot tests. Start?"], ago: 760)
        apply(store, "web", ["hook_event_name": "UserPromptSubmit", "prompt": "Add dark mode"], ago: 754)
        apply(store, "web", ["hook_event_name": "PreToolUse", "tool_name": "Agent",
                             "tool_input": ["description": "Audit color tokens", "subagent_type": "Explore"]], ago: 300)
        apply(store, "web", ["hook_event_name": "SubagentStart", "agent_id": "w1", "agent_type": "Explore"], ago: 300)
        apply(store, "web", ["hook_event_name": "PreToolUse", "tool_name": "Agent",
                             "tool_input": ["description": "Update snapshot tests", "subagent_type": "general-purpose"]], ago: 120)
        apply(store, "web", ["hook_event_name": "SubagentStart", "agent_id": "w2", "agent_type": "general-purpose"], ago: 120)
        apply(store, "web", ["hook_event_name": "PreToolUse", "tool_name": "Edit",
                             "tool_input": ["file_path": "/Users/me/web/src/theme.ts"]], ago: 4)

        apply(store, "api", ["hook_event_name": "UserPromptSubmit", "prompt": "Ship the migration"], ago: 95)
        apply(store, "api", ["hook_event_name": "PreToolUse", "tool_name": "Bash",
                             "tool_input": ["command": "npm test"]], ago: 10)

        apply(store, "docs", ["hook_event_name": "UserPromptSubmit", "prompt": "Fix the install guide"], ago: 400)
        apply(store, "docs", ["hook_event_name": "Stop",
                              "last_assistant_message": "Rewrote the install guide and fixed 4 broken links. Want me to add a troubleshooting section for Apple silicon too?"], ago: 178)

        apply(store, "cli", ["hook_event_name": "SessionStart"], ago: 3600)
        return store
    }

    private static func apply(_ store: SessionStore, _ project: String, _ payload: [String: Any], ago: TimeInterval,
                              reply: HookReply? = nil) {
        var full: [String: Any] = ["session_id": project, "cwd": "/Users/me/\(project)"]
        full.merge(payload) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: ["source": "claude", "term_program": "iTerm.app",
                                                                      "git_branch": "main", "payload": full]),
              let envelope = try? HookEnvelope.decode(data) else { return }
        store.apply(envelope, reply: reply, at: now.addingTimeInterval(-ago))
    }

    /// A reply hook waiting on a socket pair, so the session shows its reply field.
    private static func waitForReply(_ store: SessionStore, _ project: String) {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        let data = try! JSONSerialization.data(withJSONObject: [
            "source": "claude", "await_reply": true, "hook_pid": getpid(),
            "payload": ["session_id": project, "cwd": "/Users/me/\(project)", "hook_event_name": "Stop"],
        ])
        store.apply(try! HookEnvelope.decode(data), reply: .awaitReply(HookConnection(fd: fds[0])))
    }

    private static func expanded(_ store: SessionStore, selected: String? = nil) -> IslandModel {
        let model = IslandModel(store: store)
        model.isExpanded = true
        model.selectedSessionId = selected
        return model
    }

    /// The island over a dark desktop with a menu bar, cropped to the island.
    private static func render(_ model: IslandModel) -> Data? {
        let island = IslandView(model: model, onFocus: { _ in }, onDecide: { _, _, _ in }, onReply: { _, _ in },
                                onOnboarding: { _ in })
        let width = IslandModel.panelWidth + 160
        let host = NSHostingView(rootView: AnyView(
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(hex: 0x2B2F45), Color(hex: 0x15161D)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(hex: 0x1D1E26)).frame(height: model.notchHeight)
                island.frame(width: model.windowSize.width, height: model.windowSize.height)
            }
            .frame(width: width, height: model.windowSize.height)
            .environment(\.colorScheme, .dark)
        ))
        host.frame = NSRect(x: 0, y: 0, width: width, height: model.windowSize.height)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: width, height: model.windowSize.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        // Let measured heights and preferences settle.
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        let shown = model.currentSize
        let cropHeight = min(model.windowSize.height, shown.height + 70)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        guard let full = rep.cgImage,
              let cropped = full.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(full.width),
                                                     height: cropHeight * CGFloat(full.height) / host.bounds.height))
        else { return nil }
        return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
    }
}
