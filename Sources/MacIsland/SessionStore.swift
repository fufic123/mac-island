import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "sessions")

/// Folds hook events into the live list of agent sessions.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [String: AgentSession] = [:]
    /// Hooks blocked on a PermissionRequest, waiting for Allow/Deny from the island.
    private var responders: [String: PermissionResponder] = [:]

    /// Finished/idle sessions without a known pid are dropped after this long.
    static let staleAfter: TimeInterval = 30 * 60

    /// Attention first, then working, done, idle; most recent first within a group.
    var sorted: [AgentSession] {
        sessions.values.sorted {
            $0.status != $1.status ? $0.status < $1.status : $0.lastEventAt > $1.lastEventAt
        }
    }

    var needsAttention: Bool { sessions.values.contains { $0.status.needsAttention } }

    func apply(_ envelope: HookEnvelope, responder: PermissionResponder? = nil, at now: Date = .now) {
        let p = envelope.payload
        // Any later event means the request was settled elsewhere (e.g. in the terminal),
        // so release the waiting hook. Notifications don't settle anything.
        if p.hookEventName != "Notification" {
            releaseResponder(for: p.sessionId)
        }
        if p.hookEventName == "SessionEnd" {
            sessions[p.sessionId] = nil
            return
        }

        // Sessions started before the app launched show up on their first event.
        var s = sessions[p.sessionId] ?? AgentSession(id: p.sessionId, startedAt: now, lastEventAt: now)
        s.lastEventAt = now
        if let cwd = p.cwd { s.cwd = cwd }
        if let branch = envelope.gitBranch { s.gitBranch = branch.isEmpty ? nil : branch }
        if let term = envelope.termProgram, !term.isEmpty { s.termProgram = term }
        if let tty = envelope.tty, !tty.isEmpty { s.tty = tty }
        if let pid = envelope.claudePid { s.pid = pid }

        switch p.hookEventName {
        case "SessionStart":
            s.status = .idle
            s.activity = nil
        case "UserPromptSubmit":
            s.status = .working
            s.activity = "Thinking…"
            s.pendingPermission = nil
            s.permissionPreview = nil
            s.finishedAt = nil
        case "PreToolUse":
            s.status = .working
            s.activity = ToolDescriber.describe(tool: p.toolName, input: p.toolInput)
            s.finishedAt = nil
        case "PostToolUse":
            // Also how we learn a permission prompt was approved in the terminal.
            s.status = .working
            s.activity = "Thinking…"
            s.pendingPermission = nil
            s.permissionPreview = nil
        case "PermissionRequest":
            s.status = .needsPermission
            s.pendingPermission = ToolDescriber.describe(tool: p.toolName, input: p.toolInput)
            s.permissionPreview = p.toolInput?.command ?? p.toolInput?.filePath ?? p.toolInput?.url
            if let responder {
                responders[p.sessionId] = responder
                s.awaitingDecision = true
                s.permissionRequestId = UUID()
                s.permissionRequestedAt = now
            }
        case "Notification":
            applyNotification(p, to: &s)
        case "Stop":
            s.status = .done
            s.activity = nil
            s.pendingPermission = nil
            s.permissionPreview = nil
            s.finishedAt = now
        default:
            break
        }
        sessions[p.sessionId] = s
        log.info("\(s.projectName, privacy: .public)@\(s.gitBranch ?? "-", privacy: .public) pid=\(s.pid ?? -1) \(String(describing: s.status), privacy: .public): \(s.pendingPermission ?? s.activity ?? "-", privacy: .private)")
    }

    private func applyNotification(_ p: ClaudeHookPayload, to s: inout AgentSession) {
        let message = p.message?.lowercased() ?? ""
        if p.notificationType == "permission_prompt" || message.contains("permission") {
            s.status = .needsPermission
            if s.pendingPermission == nil { s.pendingPermission = p.message }
        } else if p.notificationType == "idle_prompt" || message.contains("waiting for your input") {
            // Only meaningful once Claude has stopped; don't override an active turn.
            if s.status == .done || s.status == .idle { s.status = .waitingForInput }
        }
    }

    /// Ignore clicks this soon after a request appears, so a click aimed at something
    /// else can't approve a request that just popped up under the cursor.
    static let decisionGuardInterval: TimeInterval = 0.6

    /// Answers a pending permission request from the island. `requestId` is the request the
    /// UI showed; if a newer request has replaced it, the decision is dropped.
    func decide(sessionId: String, requestId: UUID, allow: Bool, now: Date = .now) {
        guard var s = sessions[sessionId],
              s.permissionRequestId == requestId,
              let requestedAt = s.permissionRequestedAt,
              now.timeIntervalSince(requestedAt) >= Self.decisionGuardInterval,
              let responder = responders.removeValue(forKey: sessionId)
        else { return }
        allow ? responder.allow() : responder.deny()
        s.awaitingDecision = false
        s.permissionRequestId = nil
        s.permissionRequestedAt = nil
        s.pendingPermission = nil
        s.permissionPreview = nil
        s.status = .working
        s.activity = allow ? "Approved · running" : "Denied · thinking…"
        sessions[sessionId] = s
    }

    private func releaseResponder(for sessionId: String) {
        responders.removeValue(forKey: sessionId)?.close()
        sessions[sessionId]?.awaitingDecision = false
        sessions[sessionId]?.permissionRequestId = nil
        sessions[sessionId]?.permissionRequestedAt = nil
    }

    /// Drops sessions whose Claude process is gone (terminal closed without SessionEnd).
    func prune(now: Date = .now) {
        for (id, s) in sessions {
            let dead: Bool
            if let pid = s.pid {
                dead = kill(pid, 0) != 0 && errno == ESRCH
            } else {
                dead = s.status >= .done && now.timeIntervalSince(s.lastEventAt) > Self.staleAfter
            }
            if dead {
                releaseResponder(for: id)
                sessions[id] = nil
            }
        }
    }
}
