import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "sessions")

/// Folds hook events into the live list of agent sessions.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [String: AgentSession] = [:]

    /// Finished/idle sessions without a known pid are dropped after this long.
    static let staleAfter: TimeInterval = 30 * 60

    /// Attention first, then working, done, idle; most recent first within a group.
    var sorted: [AgentSession] {
        sessions.values.sorted {
            $0.status != $1.status ? $0.status < $1.status : $0.lastEventAt > $1.lastEventAt
        }
    }

    var needsAttention: Bool { sessions.values.contains { $0.status.needsAttention } }

    func apply(_ envelope: HookEnvelope, at now: Date = .now) {
        let p = envelope.payload
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
        case "PermissionRequest":
            s.status = .needsPermission
            s.pendingPermission = ToolDescriber.describe(tool: p.toolName, input: p.toolInput)
        case "Notification":
            applyNotification(p, to: &s)
        case "Stop":
            s.status = .done
            s.activity = nil
            s.pendingPermission = nil
            s.finishedAt = now
        default:
            break
        }
        sessions[p.sessionId] = s
        log.info("\(s.projectName, privacy: .public)@\(s.gitBranch ?? "-", privacy: .public) pid=\(s.pid ?? -1) \(String(describing: s.status), privacy: .public): \(s.pendingPermission ?? s.activity ?? "-", privacy: .public)")
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

    /// Drops sessions whose Claude process is gone (terminal closed without SessionEnd).
    func prune(now: Date = .now) {
        for (id, s) in sessions {
            if let pid = s.pid {
                if kill(pid, 0) != 0 && errno == ESRCH { sessions[id] = nil }
            } else if s.status >= .done, now.timeIntervalSince(s.lastEventAt) > Self.staleAfter {
                sessions[id] = nil
            }
        }
    }
}
