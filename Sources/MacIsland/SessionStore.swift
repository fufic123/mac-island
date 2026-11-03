import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "sessions")

/// Moments worth a short "peek" of the island.
enum IslandSignal: Sendable {
    case permission(project: String, phrase: String)
    case question(project: String)
    case done(sessionId: String, project: String, duration: TimeInterval?, summary: String?)
    case replied(project: String, text: String)
    case allowed(project: String, detail: String)
    case denied
    case ruleAdded(rule: String, project: String)
}

/// Folds hook events into the live list of agent sessions.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [String: AgentSession] = [:]
    /// Hooks blocked on a PermissionRequest, waiting for Allow/Deny from the island.
    private var responders: [String: PermissionResponder] = [:]
    /// Background Stop hooks waiting for a typed reply, one per session.
    private var replyWaiters: [String: HookConnection] = [:]
    @ObservationIgnored var onSignal: ((IslandSignal) -> Void)?
    /// When the last decision was made; the next queued request slides into the same spot.
    @ObservationIgnored private var lastDecisionAt: Date = .distantPast

    /// Finished/idle sessions without a known pid are dropped after this long.
    static let staleAfter: TimeInterval = 30 * 60
    /// Ignore clicks this soon after a request appears or after the previous decision, so a
    /// click aimed at something else can't approve a request that just slid under the cursor.
    static let decisionGuardInterval: TimeInterval = 0.6

    /// Attention first, then working, done, idle; most recent first within a group.
    var sorted: [AgentSession] {
        sessions.values.sorted {
            $0.status != $1.status ? $0.status < $1.status : $0.lastEventAt > $1.lastEventAt
        }
    }

    var needsAttention: Bool { sessions.values.contains { $0.status.needsAttention } }
    var isAnyWorking: Bool { sessions.values.contains { $0.status == .working } }

    /// Requests answerable from the island, oldest first.
    var pendingDecisions: [AgentSession] {
        sessions.values
            .filter { $0.awaitingDecision }
            .sorted { ($0.permissionRequestedAt ?? .distantPast) < ($1.permissionRequestedAt ?? .distantPast) }
    }

    func apply(_ envelope: HookEnvelope, reply: HookReply? = nil, at now: Date = .now) {
        let p = envelope.payload
        if envelope.awaitReply == true {
            if case let .awaitReply(connection) = reply { registerReplyWaiter(connection, for: envelope) }
            return
        }
        var responder: PermissionResponder?
        if case let .permission(r) = reply { responder = r }
        // A new turn (typed in the terminal) or the end of the session makes a pending reply moot.
        if ["UserPromptSubmit", "PreToolUse", "SessionEnd"].contains(p.hookEventName) {
            releaseReplyWaiter(for: p.sessionId)
        }
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
            s.turnStartedAt = now
            s.finishedAt = nil
            clearPermission(&s)
        case "PreToolUse" where p.toolName == "AskUserQuestion":
            s.status = .question
            s.question = p.toolInput?.questions?.first?.question
            onSignal?(.question(project: s.projectName))
        case "PreToolUse":
            s.status = .working
            s.activity = ToolDescriber.describe(tool: p.toolName, input: p.toolInput)
            if s.turnStartedAt == nil { s.turnStartedAt = now }
            s.finishedAt = nil
        case "PostToolUse":
            // Also how we learn a permission prompt was approved in the terminal.
            s.status = .working
            s.activity = "Thinking…"
            s.question = nil
            clearPermission(&s)
        case "PermissionRequest" where p.toolName == "AskUserQuestion":
            // Answered via the question UI / terminal, not Allow/Deny.
            responder?.close()
        case "PermissionRequest":
            s.status = .needsPermission
            s.permissionTool = p.toolName
            s.pendingPermission = ToolDescriber.permissionAction(tool: p.toolName, input: p.toolInput)
            s.permissionPreview = p.toolInput?.command ?? p.toolInput?.filePath ?? p.toolInput?.url
            s.permissionReason = p.toolName == "Bash" ? p.toolInput?.description : nil
            s.permissionRequestedAt = now
            if let responder {
                responders[p.sessionId] = responder
                s.awaitingDecision = true
                s.permissionRequestId = UUID()
                s.alwaysAllowLabel = responder.alwaysAllowLabel
            }
            onSignal?(.permission(project: s.projectName, phrase: ToolDescriber.permissionPhrase(tool: p.toolName)))
        case "Notification":
            applyNotification(p, to: &s, now: now)
        case "Stop":
            let wasWorking = s.status == .working || s.status.needsAttention
            s.status = .done
            s.activity = nil
            s.question = nil
            clearPermission(&s)
            s.finishedAt = now
            s.lastTurnDuration = s.turnStartedAt.map { now.timeIntervalSince($0) }
            s.turnStartedAt = nil
            if let message = p.lastAssistantMessage, !message.isEmpty { s.lastMessage = message }
            if wasWorking {
                onSignal?(.done(sessionId: s.id, project: s.projectName, duration: s.lastTurnDuration,
                                summary: ToolDescriber.summary(s.lastMessage)))
            }
        default:
            break
        }
        sessions[p.sessionId] = s
        log.info("\(s.projectName, privacy: .public)@\(s.gitBranch ?? "-", privacy: .public) pid=\(s.pid ?? -1) \(String(describing: s.status), privacy: .public): \(s.pendingPermission ?? s.activity ?? "-", privacy: .private)")
    }

    private func applyNotification(_ p: ClaudeHookPayload, to s: inout AgentSession, now: Date) {
        let message = p.message?.lowercased() ?? ""
        if p.notificationType == "permission_prompt" || message.contains("permission") {
            // Prompt shown in the terminal without our hook holding it (e.g. hook not installed).
            if s.status != .needsPermission {
                s.status = .needsPermission
                s.pendingPermission = p.message
                s.permissionRequestedAt = now
            }
        } else if p.notificationType == "idle_prompt" || message.contains("waiting for your input") {
            // Only meaningful once Claude has stopped; don't override an active turn.
            if s.status == .done || s.status == .idle { s.status = .waitingForInput }
        }
    }

    /// Answers a pending permission request from the island. `requestId` is the request the
    /// UI showed; if a newer request has replaced it, the decision is dropped.
    func decide(sessionId: String, requestId: UUID, decision: PermissionDecision, now: Date = .now) {
        guard var s = sessions[sessionId],
              s.permissionRequestId == requestId,
              let requestedAt = s.permissionRequestedAt,
              now.timeIntervalSince(requestedAt) >= Self.decisionGuardInterval,
              now.timeIntervalSince(lastDecisionAt) >= Self.decisionGuardInterval,
              let responder = responders.removeValue(forKey: sessionId)
        else { return }
        let rule = responder.alwaysAllowRule
        responder.respond(decision)
        lastDecisionAt = now

        let command = s.permissionTool == "Bash" ? ToolDescriber.firstLine(s.permissionPreview, limit: 30) : nil
        switch decision {
        case .allow:
            onSignal?(.allowed(project: s.projectName, detail: command.map { "is running \($0)" } ?? "continues"))
        case .alwaysAllow:
            onSignal?(.ruleAdded(rule: rule ?? s.permissionTool ?? "tool", project: s.projectName))
        case .deny:
            onSignal?(.denied)
        }
        clearPermission(&s)
        s.status = .working
        s.activity = decision == .deny ? "Thinking…" : (command.map { "Running \($0)" } ?? "Working")
        sessions[sessionId] = s
    }

    /// Sends a reply typed in the island to Claude via the waiting background Stop hook.
    func reply(sessionId: String, text: String, now: Date = .now) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let waiter = replyWaiters.removeValue(forKey: sessionId),
              var s = sessions[sessionId]
        else { return }
        waiter.send(Data(text.utf8))
        s.canReply = false
        s.status = .working
        s.activity = "Thinking…"
        s.turnStartedAt = now
        s.finishedAt = nil
        sessions[sessionId] = s
        onSignal?(.replied(project: s.projectName, text: text))
    }

    private func registerReplyWaiter(_ connection: HookConnection, for envelope: HookEnvelope) {
        let id = envelope.payload.sessionId
        replyWaiters.removeValue(forKey: id)?.close()
        replyWaiters[id] = connection
        // The background hook can arrive before the regular Stop event.
        var s = sessions[id] ?? AgentSession(id: id, startedAt: .now, lastEventAt: .now)
        if let cwd = envelope.payload.cwd { s.cwd = cwd }
        if let message = envelope.payload.lastAssistantMessage, !message.isEmpty { s.lastMessage = message }
        if let pid = envelope.claudePid { s.pid = pid }
        s.canReply = true
        sessions[id] = s
    }

    private func releaseReplyWaiter(for sessionId: String) {
        replyWaiters.removeValue(forKey: sessionId)?.close()
        sessions[sessionId]?.canReply = false
    }

    private func clearPermission(_ s: inout AgentSession) {
        s.permissionTool = nil
        s.pendingPermission = nil
        s.permissionPreview = nil
        s.permissionReason = nil
        s.alwaysAllowLabel = nil
        s.awaitingDecision = false
        s.permissionRequestId = nil
        s.permissionRequestedAt = nil
    }

    private func releaseResponder(for sessionId: String) {
        responders.removeValue(forKey: sessionId)?.close()
        sessions[sessionId]?.awaitingDecision = false
        sessions[sessionId]?.permissionRequestId = nil
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
                releaseReplyWaiter(for: id)
                sessions[id] = nil
            }
        }
    }
}
