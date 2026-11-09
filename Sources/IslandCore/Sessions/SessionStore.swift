import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.fufic123.macisland", category: "sessions")

/// Moments worth a short "peek" of the island.
public enum IslandSignal: Sendable {
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
public final class SessionStore {
    public private(set) var sessions: [String: AgentSession] = [:]
    /// Hooks blocked on a PermissionRequest, waiting for Allow/Deny from the island.
    private var responders: [String: PermissionResponder] = [:]
    /// Background Stop hooks waiting for a typed reply, one per session.
    private var replyWaiters: [String: HookConnection] = [:]
    /// The process of each waiting reply hook, when the hook sent it.
    @ObservationIgnored private var replyWaiterPids: [String: Int32] = [:]
    @ObservationIgnored public var onSignal: ((IslandSignal) -> Void)?
    /// When the last decision was made; the next queued request slides into the same spot.
    @ObservationIgnored private var lastDecisionAt: Date = .distantPast
    /// Transcript modification date last looked at, per session.
    @ObservationIgnored private var transcriptChecked: [String: Date] = [:]
    @ObservationIgnored private let costMeter = TranscriptCost()
    @ObservationIgnored private let desktopTitles = DesktopTitles()
    @ObservationIgnored private var costRefreshRunning = false
    @ObservationIgnored private let dailyCost = DailyCost()
    @ObservationIgnored private var dailyCostCheckedAt: Date = .distantPast
    /// All conversations' cost today at API prices.
    public private(set) var todayCost: Double?

    /// Finished/idle sessions without a known pid are dropped after this long.
    public static let staleAfter: TimeInterval = 30 * 60
    /// Ignore clicks this soon after a request appears or after the previous decision, so a
    /// click aimed at something else can't approve a request that just slid under the cursor.
    public static let decisionGuardInterval: TimeInterval = 0.6

    public init() {}

    /// Attention first, then working, done, idle; most recent first within a group.
    public var sorted: [AgentSession] {
        sessions.values.sorted {
            $0.status != $1.status ? $0.status < $1.status : $0.lastEventAt > $1.lastEventAt
        }
    }

    public var needsAttention: Bool { sessions.values.contains { $0.status.needsAttention } }
    public var isAnyWorking: Bool { sessions.values.contains { $0.status == .working } }

    /// Requests answerable from the island, oldest first.
    public var pendingDecisions: [AgentSession] {
        sessions.values
            .filter { $0.awaitingDecision }
            .sorted { ($0.permissionRequestedAt ?? .distantPast) < ($1.permissionRequestedAt ?? .distantPast) }
    }

    public func apply(_ envelope: HookEnvelope, reply: HookReply? = nil, at now: Date = .now) {
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
        // A later event from the same agent means the request was settled elsewhere (e.g. in the
        // terminal), so release the waiting hook. Notifications don't settle anything, and other
        // subagents keep working while one waits.
        if p.hookEventName == "UserPromptSubmit"
            || (p.hookEventName != "Notification" && sessions[p.sessionId]?.permissionAgentId == p.agentId) {
            releaseResponder(for: p.sessionId)
        }
        if p.hookEventName == "SessionEnd" {
            sessions[p.sessionId] = nil
            return
        }

        // Sessions started before the app launched show up on their first event.
        var s = sessions[p.sessionId] ?? AgentSession(id: p.sessionId, startedAt: now, lastEventAt: now)
        s.lastEventAt = now
        // A subagent may run in its own worktree; its cwd and branch aren't the session's, and
        // "Open terminal" must open the main conversation's folder.
        // A worktree subagent's cwd is "<project>/.claude/worktrees/agent-<id>", which also tells
        // the main folder when the subagent's event is the first one seen (e.g. after a restart).
        let fromSubagent = p.agentId != nil || p.cwd.map(Self.isSubagentWorktree) == true
        if let cwd = p.cwd, !fromSubagent || s.cwd == nil { s.cwd = Self.mainFolder(of: cwd) }
        if let branch = envelope.gitBranch, !fromSubagent || s.gitBranch == nil {
            s.gitBranch = branch.isEmpty ? nil : branch
        }
        if let term = envelope.termProgram, !term.isEmpty { s.termProgram = term }
        if let tty = envelope.tty, !tty.isEmpty { s.tty = tty }
        if let pid = envelope.claudePid { s.pid = pid }
        if let path = p.transcriptPath, p.agentId == nil { s.transcriptPath = path }
        // A subagent's event can be the first seen (after a restart); its transcript sits in
        // "<session>/subagents/", next to the session's own "<session>.jsonl".
        if s.transcriptPath == nil, let path = p.transcriptPath {
            s.transcriptPath = path.range(of: "/subagents/").map { String(path[..<$0.lowerBound]) + ".jsonl" } ?? path
        }

        // Tool calls inside a subagent update that subagent, not the session's own line.
        if let agentId = p.agentId, ["PreToolUse", "PostToolUse"].contains(p.hookEventName),
           p.toolName != "AskUserQuestion" {
            guard let i = subagentIndex(&s, id: agentId, type: p.agentType, now: now) else {
                sessions[p.sessionId] = s
                return
            }
            if p.hookEventName == "PreToolUse" {
                s.subagents[i].activity = ToolDescriber.describe(tool: p.toolName, input: p.toolInput)
            }
            if p.hookEventName == "PostToolUse", s.permissionAgentId == agentId { clearPermission(&s) }
            if s.status == .needsPermission, s.pendingPermission == nil { s.status = .working }
            sessions[p.sessionId] = s
            return
        }
        if ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest"].contains(p.hookEventName) {
            s.wasInterrupted = false
        }

        switch p.hookEventName {
        case "SessionStart":
            s.status = .idle
            s.activity = nil
        case "UserPromptSubmit":
            s.suggestion = nil
            s.status = .working
            s.activity = "Thinking…"
            s.turnStartedAt = now
            s.finishedAt = nil
            clearPermission(&s)
            s.subagents.removeAll { $0.state != .running }
            s.pendingAgentTasks = []
        case "PreToolUse" where p.toolName == "AskUserQuestion":
            s.status = .question
            s.question = p.toolInput?.questions?.first?.question
            onSignal?(.question(project: s.projectName))
        case "PreToolUse":
            s.suggestion = nil
            s.status = .working
            s.activity = ToolDescriber.describe(tool: p.toolName, input: p.toolInput)
            if p.toolName == "Task" || p.toolName == "Agent" {
                s.pendingAgentTasks.append(PendingAgentTask(task: p.toolInput?.description, type: p.toolInput?.subagentType))
            }
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
            s.permissionAgentId = p.agentId
            if let responder {
                responders[p.sessionId] = responder
                s.awaitingDecision = true
                s.permissionRequestId = UUID()
                s.alwaysAllowLabel = responder.alwaysAllowLabel
            }
            onSignal?(.permission(project: s.projectName, phrase: ToolDescriber.permissionPhrase(tool: p.toolName)))
        case "Notification" where s.status == .working && Self.isIdlePrompt(p):
            // The terminal is waiting for input mid-turn: Esc while Claude was still thinking,
            // which writes no interrupt marker and sends no Stop.
            sessions[p.sessionId] = s
            markInterrupted(p.sessionId, now: now)
            return
        case "Notification":
            applyNotification(p, to: &s, now: now)
        case "StopFailure":
            // The turn ended on an API error (rate limit, overload, …); Stop doesn't follow.
            sessions[p.sessionId] = s
            markInterrupted(p.sessionId, now: now, byUser: false)
            return
        case "SubagentStart":
            log.info("subagent start type=\(p.agentType ?? "-", privacy: .public)")
            if let id = p.agentId { _ = subagentIndex(&s, id: id, type: p.agentType, now: now) }
        case "SubagentStop":
            log.info("subagent stop type=\(p.agentType ?? "-", privacy: .public)")
            if let id = p.agentId, !s.subagents.contains(where: { $0.id == id }), !s.hiddenAgents.contains(id),
               Transcript.subagentMeta(sessionTranscript: s.transcriptPath, agentId: id) != nil {
                _ = subagentIndex(&s, id: id, type: p.agentType, now: now)
            }
            if let id = p.agentId, s.hiddenAgents.contains(id) || !s.subagents.contains(where: { $0.id == id }) {
                // An internal fork, not shown as a subagent. Its text becomes a one-click reply sent
                // as the user, so only the prompt-suggestion fork qualifies (see isPromptSuggestion).
                s.hiddenAgents.remove(id)
                if isPromptSuggestion(p, in: s, now: now) {
                    s.suggestion = p.lastAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                break
            }
            let i = p.agentId.flatMap { id in subagentIndex(&s, id: id, type: p.agentType, now: now) }
                ?? s.subagents.firstIndex { $0.state == .running }
            if let i {
                s.subagents[i].state = .done
                s.subagents[i].activity = nil
                s.subagents[i].finishedAt = now
                s.subagents[i].summary = ToolDescriber.summary(p.lastAssistantMessage)
            }
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
        log.info("\(s.projectName, privacy: .private)@\(s.gitBranch ?? "-", privacy: .public) pid=\(s.pid ?? -1) \(String(describing: s.status), privacy: .public): \(s.pendingPermission ?? s.activity ?? "-", privacy: .private)")
    }

    /// Whether a finished internal fork is Claude Code's prompt suggestion. Its output is sent as
    /// the user's reply in one click, so this is strict: a real subagent's output (which may echo
    /// web pages or files) must never qualify. It has to come right after the turn ended, with no
    /// launched Task unaccounted for, no subagent still running, an agent type that is absent or
    /// names the suggestion fork, and short single-line text.
    private func isPromptSuggestion(_ p: ClaudeHookPayload, in s: AgentSession, now: Date) -> Bool {
        let type = p.agentType ?? ""
        guard type.isEmpty || type.lowercased().contains("prompt_suggestion") || type.lowercased() == "suggestion",
              s.status == .done || s.status == .waitingForInput,
              let finished = s.finishedAt, now.timeIntervalSince(finished) < 60,
              s.pendingAgentTasks.isEmpty,
              s.runningSubagents == 0,
              let text = p.lastAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 200, !text.contains("\n"),
              // With nothing to suggest the fork answers with a placeholder like "(no suggestion)".
              !(text.hasPrefix("(") && text.hasSuffix(")")),
              !text.lowercased().contains("no suggestion")
        else { return false }
        return true
    }

    /// Index of the subagent, creating it (matched to the oldest launched Task) if it's new.
    /// Nil for Claude Code's internal forks, which start without a Task call.
    private func subagentIndex(_ s: inout AgentSession, id: String, type: String?, now: Date) -> Int? {
        if let i = s.subagents.firstIndex(where: { $0.id == id }) {
            if s.subagents[i].type == nil { s.subagents[i].type = type }
            return i
        }
        if s.hiddenAgents.contains(id) { return nil }
        guard let match = s.pendingAgentTasks.firstIndex(where: { $0.type == nil || $0.type == type }) else {
            // Launched before this app saw the Task call (e.g. it was restarted): Claude Code's
            // metadata for a Task-launched subagent carries its description; forks have none.
            if let meta = Transcript.subagentMeta(sessionTranscript: s.transcriptPath, agentId: id) {
                s.subagents.append(Subagent(id: id, type: type ?? meta.type, task: meta.description, startedAt: now))
                return s.subagents.count - 1
            }
            s.hiddenAgents.insert(id)
            return nil
        }
        let launched = Optional(s.pendingAgentTasks.remove(at: match))
        s.subagents.append(Subagent(id: id, type: type ?? launched?.type, task: launched?.task, startedAt: now))
        return s.subagents.count - 1
    }

    /// Esc in the terminal sends no hook event, but Claude writes "[Request interrupted by user]"
    /// into the transcript. Checked for sessions that look busy, only when the file changed.
    public func checkInterrupts(now: Date = .now) {
        for (id, s) in sessions where s.status == .working || s.status.needsAttention {
            guard let path = s.transcriptPath,
                  let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  modified != transcriptChecked[id]
            else { continue }
            transcriptChecked[id] = modified
            // An interrupt written before this turn started is the previous turn's.
            guard modified > (s.turnStartedAt ?? .distantPast), Transcript.endsWithInterrupt(path) else { continue }
            markInterrupted(id, now: now)
        }
    }

    private func markInterrupted(_ id: String, now: Date, byUser: Bool = true) {
        releaseResponder(for: id)
        guard var s = sessions[id] else { return }
        s.status = .idle
        s.wasInterrupted = byUser
        if !byUser { s.lastMessage = "The turn stopped on an API error." }
        s.activity = nil
        s.question = nil
        clearPermission(&s)
        s.lastTurnDuration = s.turnStartedAt.map { now.timeIntervalSince($0) }
        s.turnStartedAt = nil
        s.finishedAt = nil
        for i in s.subagents.indices where s.subagents[i].state == .running {
            s.subagents[i].state = .stopped
            s.subagents[i].activity = nil
            s.subagents[i].finishedAt = now
        }
        s.pendingAgentTasks = []
        s.lastEventAt = now
        sessions[id] = s
        log.info("\(s.projectName, privacy: .private) \(byUser ? "interrupted by the user" : "stopped on an API error", privacy: .public)")
    }

    private static func isIdlePrompt(_ p: ClaudeHookPayload) -> Bool {
        p.notificationType == "idle_prompt" || (p.message?.lowercased().contains("waiting for your input") ?? false)
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
        } else if Self.isIdlePrompt(p) {
            // Only meaningful once Claude has stopped; don't override an active turn.
            if s.status == .done || s.status == .idle { s.status = .waitingForInput }
        }
    }

    /// Answers a pending permission request from the island. `requestId` is the request the
    /// UI showed; if a newer request has replaced it, the decision is dropped.
    public func decide(sessionId: String, requestId: UUID, decision: PermissionDecision, now: Date = .now) {
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
    public func reply(sessionId: String, text: String, now: Date = .now) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let waiter = replyWaiters.removeValue(forKey: sessionId),
              var s = sessions[sessionId]
        else { return }
        replyWaiterPids.removeValue(forKey: sessionId)
        waiter.send(Data(text.utf8))
        s.canReply = false
        s.suggestion = nil
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
        replyWaiterPids[id] = envelope.hookPid
        // The background hook can arrive before the regular Stop event.
        var s = sessions[id] ?? AgentSession(id: id, startedAt: .now, lastEventAt: .now)
        if let cwd = envelope.payload.cwd, (envelope.payload.agentId == nil && !Self.isSubagentWorktree(cwd)) || s.cwd == nil {
            s.cwd = Self.mainFolder(of: cwd)
        }
        if let message = envelope.payload.lastAssistantMessage, !message.isEmpty { s.lastMessage = message }
        if let pid = envelope.claudePid { s.pid = pid }
        s.canReply = true
        sessions[id] = s
    }

    /// Drops reply hooks whose process is gone, so the island stops offering a reply they can't deliver.
    public func releaseDeadReplyWaiters() {
        for (id, pid) in replyWaiterPids where kill(pid, 0) != 0 && errno == ESRCH {
            releaseReplyWaiter(for: id)
        }
    }

    private func releaseReplyWaiter(for sessionId: String) {
        replyWaiterPids.removeValue(forKey: sessionId)
        replyWaiters.removeValue(forKey: sessionId)?.close()
        sessions[sessionId]?.canReply = false
    }

    private func clearPermission(_ s: inout AgentSession) {
        s.permissionTool = nil
        s.permissionAgentId = nil
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
    public func prune(now: Date = .now) {
        for (id, s) in sessions {
            let dead: Bool
            if let pid = s.pid {
                dead = kill(pid, 0) != 0 && errno == ESRCH
            } else {
                dead = s.status >= .done && now.timeIntervalSince(s.lastEventAt) > Self.staleAfter
            }
            if dead {
                if let path = s.transcriptPath { costMeter.forget(transcriptPath: path) }
                releaseResponder(for: id)
                releaseReplyWaiter(for: id)
                sessions[id] = nil
                transcriptChecked[id] = nil
            }
        }
    }

    /// Recomputes each session's cost from its transcripts off the main thread.
    public func refreshCosts() {
        guard !costRefreshRunning else { return }
        let targets = sessions.compactMap { id, s in s.transcriptPath.map { (id, $0) } }
        // The daily total walks every project folder, so less often.
        let daily: DailyCost? = Date.now.timeIntervalSince(dailyCostCheckedAt) > 10 ? dailyCost : nil
        if daily != nil { dailyCostCheckedAt = .now }
        guard !targets.isEmpty || daily != nil else { return }
        costRefreshRunning = true
        let meter = costMeter
        Task.detached(priority: .utility) {
            let costs = targets.map { ($0.0, meter.cost(transcriptPath: $0.1)) }
            let today = daily?.total()
            await MainActor.run {
                self.costRefreshRunning = false
                if let today, today != self.todayCost { self.todayCost = today }
                for (id, cost) in costs where self.sessions[id] != nil && self.sessions[id]?.cost != cost {
                    self.sessions[id]?.cost = cost
                }
            }
        }
    }

    private static let worktreeMarker = "/.claude/worktrees/agent-"

    static func isSubagentWorktree(_ cwd: String) -> Bool { cwd.contains(worktreeMarker) }

    /// The project folder a subagent's worktree belongs to; other paths unchanged.
    static func mainFolder(of cwd: String) -> String {
        guard let r = cwd.range(of: worktreeMarker) else { return cwd }
        return String(cwd[..<r.lowerBound])
    }

    // MARK: Persistence
    // Sessions live only in memory and hooks don't replay, so a restart (an update, a crash)
    // would forget every open conversation until it next does something. Saved after changes,
    // restored on launch; dead ones go on the next prune.

    @ObservationIgnored private var lastSaved: Data?

    public func save(to url: URL) {
        guard let data = try? JSONEncoder().encode(Array(sessions.values)), data != lastSaved else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: url, options: .atomic)) != nil { lastSaved = data }
    }

    public func restore(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([AgentSession].self, from: data)
        else { return }
        lastSaved = data
        for var s in saved where sessions[s.id] == nil {
            // Waiting hooks belonged to the old process; the terminal still has the prompt.
            s.awaitingDecision = false
            s.canReply = false
            // Re-checked against the subagents' metadata on their next event.
            s.hiddenAgents = []
            sessions[s.id] = s
        }
        log.info("restored \(saved.count) sessions")
        prune()
    }

    // MARK: Subagent discovery

    @ObservationIgnored private var subagentsCheckedAt: Date = .distantPast

    /// A running subagent writes its transcript on every step; this long without a write it was
    /// killed with its session (Claude Code sends no SubagentStop then).
    static let subagentQuietLimit: TimeInterval = 30 * 60

    /// Syncs subagents with Claude Code's subagent metadata and transcripts: adds running ones that
    /// sent no hook event yet (launched before the app started, or quietly waiting on CI), and
    /// ends ones that finished or died without a SubagentStop.
    public func discoverSubagents(now: Date = .now) {
        guard now.timeIntervalSince(subagentsCheckedAt) > 5 else { return }
        subagentsCheckedAt = now
        // Claude Desktop names a chat after its first turn and may rename it later.
        for (id, s) in sessions where s.termProgram == "claude-desktop" {
            let title = desktopTitles.title(forSession: id)
            if let title, title != s.desktopTitle { sessions[id]?.desktopTitle = title }
        }
        for (id, s) in sessions {
            guard let path = s.transcriptPath else { continue }
            var updated = s
            for info in Transcript.subagents(sessionTranscript: path) {
                let alive = !info.finished && now.timeIntervalSince(info.modified) < Self.subagentQuietLimit
                if let i = updated.subagents.firstIndex(where: { $0.id == info.id }) {
                    guard updated.subagents[i].state == .running, !alive else { continue }
                    updated.subagents[i].state = info.finished ? .done : .stopped
                    updated.subagents[i].activity = nil
                    updated.subagents[i].finishedAt = info.modified
                } else if alive {
                    updated.hiddenAgents.remove(info.id)
                    updated.subagents.append(Subagent(id: info.id, type: info.type, task: info.description, startedAt: info.started))
                }
            }
            if updated.subagents.map(\.state) != s.subagents.map(\.state) || updated.subagents.count != s.subagents.count {
                sessions[id] = updated
            }
        }
    }
}
