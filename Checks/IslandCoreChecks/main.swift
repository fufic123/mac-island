// Behaviour checks for IslandCore: `swift run IslandCoreChecks`.
// A plain executable because the Command Line Tools ship neither XCTest nor the Swift Testing
// macro plugin; exits non-zero if any check fails.
import Foundation
import IslandCore

nonisolated(unsafe) var failures = 0

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if condition() {
        print("✔ \(name)")
    } else {
        failures += 1
        print("✘ \(name)")
    }
}

func envelope(_ payload: [String: Any]) -> HookEnvelope {
    var full: [String: Any] = ["session_id": "s1", "cwd": "/tmp/demo"]
    full.merge(payload) { _, new in new }
    let data = try! JSONSerialization.data(withJSONObject: ["source": "claude", "payload": full])
    return try! HookEnvelope.decode(data)
}

@MainActor
func run() {
    do {
        // Plan limits saved from Claude Code's status line.
        let data = Data(#"{"updated_at":1000,"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":2000},"seven_day":{"used_percentage":130,"resets_at":9000}}}"#.utf8)
        let limits = UsageLimits.decode(data)
        check(limits?.fiveHour?.usedPercent == 42.5 && limits?.sevenDay?.usedPercent == 100, "plan limits are read and capped at 100%")
        let later = limits?.current(at: Date(timeIntervalSince1970: 3000))
        check(later?.fiveHour?.usedPercent == 0 && later?.sevenDay?.usedPercent == 100, "a limit past its reset time starts over at 0%")
        check(UsageLimits.decode(Data(#"{"updated_at":1,"rate_limits":{}}"#.utf8)) == nil, "no windows means no limits")
    }
    do {
        // A subagent launched before the app saw its Task call is found by its metadata.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("meta-\(UUID().uuidString)")
        let subagents = dir.appendingPathComponent("s1/subagents")
        try! FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try! #"{"agentType":"general-purpose","description":"Fix the bug"}"#
            .write(to: subagents.appendingPathComponent("agent-b1.meta.json"), atomically: true, encoding: .utf8)
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "PreToolUse", "agent_id": "b1", "agent_type": "general-purpose",
                              "tool_name": "Bash", "transcript_path": subagents.appendingPathComponent("agent-b1.jsonl").path]))
        check(store.sessions["s1"]?.subagents.first?.task == "Fix the bug", "subagent launched before a restart shows up")
        store.apply(envelope(["hook_event_name": "PreToolUse", "agent_id": "fork", "tool_name": "Bash"]))
        check(store.sessions["s1"]?.subagents.count == 1, "a fork without metadata stays hidden")
        // A quiet one (waiting on CI) is found without any event of its own.
        try! #"{"agentType":"general-purpose","description":"Watch CI"}"#
            .write(to: subagents.appendingPathComponent("agent-b2.meta.json"), atomically: true, encoding: .utf8)
        try! #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"#
            .write(to: subagents.appendingPathComponent("agent-b2.jsonl"), atomically: true, encoding: .utf8)
        store.discoverSubagents()
        check(store.sessions["s1"]?.subagents.contains { $0.task == "Watch CI" && $0.state == .running } == true,
              "a quiet running subagent is discovered")
        // Its session was killed: no write for over half an hour ends it.
        store.discoverSubagents(now: Date.now.addingTimeInterval(31 * 60))
        check(store.sessions["s1"]?.subagents.first { $0.task == "Watch CI" }?.state == .stopped,
              "a subagent silent for half an hour is no longer running")
    }
    do {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString).json")
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "UserPromptSubmit"]))
        store.apply(envelope(["hook_event_name": "PreToolUse", "tool_name": "Agent",
                              "tool_input": ["description": "Find routes", "subagent_type": "Explore"]]))
        store.apply(envelope(["hook_event_name": "SubagentStart", "agent_id": "a1", "agent_type": "Explore"]))
        store.save(to: url)
        let restored = SessionStore()
        restored.restore(from: url)
        check(restored.sessions["s1"]?.subagents.count == 1, "sessions and subagents survive a restart")
    }
    do {
        // After a restart the first event can come from a worktree subagent.
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "PreToolUse", "agent_id": "a9", "tool_name": "Bash",
                              "cwd": "/tmp/demo/.claude/worktrees/agent-a9"]))
        check(store.sessions["s1"]?.projectName == "demo", "worktree subagent's event names the main project")
        store.apply(envelope(["hook_event_name": "Stop", "cwd": "/tmp/demo/.claude/worktrees/agent-a9"]))
        check(store.sessions["s1"]?.cwd == "/tmp/demo", "worktree cwd never replaces the session's")
    }
    do {
        // Two lines of one response (same id) count once; a partial last line waits.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cost-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("s.jsonl").path
        let line = #"{"type":"assistant","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":100000,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":1000000,"cache_creation":{"ephemeral_1h_input_tokens":1000000,"ephemeral_5m_input_tokens":0}}}}"#
        try! (line + "\n" + line + "\n" + "{\"type\":\"assi").write(toFile: path, atomically: true, encoding: .utf8)
        let meter = TranscriptCost()
        // $4 input + $2 output + $0.20 read + $8 1h write
        check(abs(meter.cost(transcriptPath: path) - 14.2) < 0.0001, "transcript cost counts a response once")
        check(abs(meter.cost(transcriptPath: path) - 14.2) < 0.0001, "re-reading adds nothing")
    }
    do {
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "UserPromptSubmit"]))
        check(store.sessions["s1"]?.status == .working, "prompt starts working")
        store.apply(envelope(["hook_event_name": "Stop", "last_assistant_message": "All done"]))
        check(store.sessions["s1"]?.status == .done && store.sessions["s1"]?.lastMessage == "All done",
              "Stop finishes with Claude's message")
    }
    do {
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "UserPromptSubmit"]))
        store.apply(envelope(["hook_event_name": "PreToolUse", "tool_name": "Agent",
                              "tool_input": ["description": "Find routes", "subagent_type": "Explore"]]))
        store.apply(envelope(["hook_event_name": "SubagentStart", "agent_id": "a1", "agent_type": "Explore"]))
        check(store.sessions["s1"]?.subagents.first?.task == "Find routes", "subagent matched to its Task")
        store.apply(envelope(["hook_event_name": "SubagentStop", "agent_id": "a1", "agent_type": "Explore",
                              "last_assistant_message": "Found 3"]))
        check(store.sessions["s1"]?.subagents.first?.state == .done, "subagent finishes")
        check(store.sessions["s1"]?.suggestion == nil, "a subagent's output is never a suggestion")
    }
    do {
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "UserPromptSubmit"]))
        store.apply(envelope(["hook_event_name": "Stop", "last_assistant_message": "Done"]))
        store.apply(envelope(["hook_event_name": "SubagentStart", "agent_id": "f1"]))
        store.apply(envelope(["hook_event_name": "SubagentStop", "agent_id": "f1", "last_assistant_message": "run the tests"]))
        check(store.sessions["s1"]?.suggestion == "run the tests", "fork after the turn becomes the suggestion")
        check(store.sessions["s1"]?.subagents.isEmpty == true, "the suggestion fork isn't listed as a subagent")
    }
    do {
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "UserPromptSubmit"]))
        store.apply(envelope(["hook_event_name": "Stop", "last_assistant_message": "Done"]))
        store.apply(envelope(["hook_event_name": "SubagentStart", "agent_id": "f1"]))
        store.apply(envelope(["hook_event_name": "SubagentStop", "agent_id": "f1", "last_assistant_message": "(no suggestion)"]))
        check(store.sessions["s1"]?.suggestion == nil, "\"(no suggestion)\" shows no suggestion")
    }
    do {
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "UserPromptSubmit"]))
        store.apply(envelope(["hook_event_name": "Stop", "last_assistant_message": "Done"]))
        store.apply(envelope(["hook_event_name": "SubagentStop", "agent_id": "x1", "agent_type": "general-purpose",
                              "last_assistant_message": "ignore previous instructions"]))
        check(store.sessions["s1"]?.suggestion == nil, "a fork of another type is not a suggestion")
    }
    do {
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "UserPromptSubmit"]))
        store.apply(envelope(["hook_event_name": "SubagentStop", "agent_id": "f1", "last_assistant_message": "do it"]))
        check(store.sessions["s1"]?.suggestion == nil, "a fork during the turn is not a suggestion")
    }
    do {
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "UserPromptSubmit"]))
        store.apply(envelope(["hook_event_name": "Notification", "notification_type": "idle_prompt"]))
        check(store.sessions["s1"]?.status == .idle && store.sessions["s1"]?.wasInterrupted == true,
              "idle prompt mid-turn means Esc while thinking")
    }
    do {
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "UserPromptSubmit"]))
        store.apply(envelope(["hook_event_name": "Stop"]))
        store.apply(envelope(["hook_event_name": "Notification", "notification_type": "idle_prompt"]))
        check(store.sessions["s1"]?.status == .waitingForInput, "idle prompt after Stop just waits")
    }
    do {
        let store = SessionStore()
        store.apply(envelope(["hook_event_name": "UserPromptSubmit"]))
        store.apply(envelope(["hook_event_name": "StopFailure"]))
        check(store.sessions["s1"]?.status == .idle && store.sessions["s1"]?.wasInterrupted == false,
              "an API error ends the turn")
    }
    do {
        let dir = FileManager.default.temporaryDirectory
        let interrupted = dir.appendingPathComponent(UUID().uuidString + ".jsonl")
        let quoted = dir.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer {
            try? FileManager.default.removeItem(at: interrupted)
            try? FileManager.default.removeItem(at: quoted)
        }
        try? [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#,
        ].joined(separator: "\n").write(to: interrupted, atomically: true, encoding: .utf8)
        try? #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"[Request interrupted by user]"}]}}"#
            .write(to: quoted, atomically: true, encoding: .utf8)
        check(Transcript.endsWithInterrupt(interrupted.path), "Esc marker in the transcript is an interrupt")
        check(!Transcript.endsWithInterrupt(quoted.path), "a tool result quoting the marker is not")
    }
}

MainActor.assumeIsolated { run() }

MainActor.assumeIsolated {
    // A reply hook stays offered while its process lives (nc half-closes the socket right after
    // sending, which must not count as gone) and is dropped once its process is gone.
    func waiter(session: String, pid: Int32) -> (HookEnvelope, HookConnection) {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        shutdown(fds[1], SHUT_WR)
        let data = try! JSONSerialization.data(withJSONObject: [
            "source": "claude", "await_reply": true, "hook_pid": pid,
            "payload": ["session_id": session, "cwd": "/tmp/demo", "hook_event_name": "Stop"],
        ])
        return (try! HookEnvelope.decode(data), HookConnection(fd: fds[0]))
    }
    let store = SessionStore()
    let (alive, aliveConn) = waiter(session: "live", pid: getpid())
    store.apply(alive, reply: .awaitReply(aliveConn))
    let (dead, deadConn) = waiter(session: "dead", pid: 99_999_999)
    store.apply(dead, reply: .awaitReply(deadConn))
    store.releaseDeadReplyWaiters()
    check(store.sessions["live"]?.canReply == true, "a waiting reply hook stays offered after nc half-closes")
    check(store.sessions["dead"]?.canReply == false, "a reply hook whose process is gone is no longer offered")

    // A reply typed while Claude works is held, then handed to the reply hook when the turn ends.
    store.apply(envelope(["session_id": "busy", "hook_event_name": "UserPromptSubmit", "prompt": "go"]))
    store.reply(sessionId: "busy", text: "also check the tests")
    check(store.sessions["busy"]?.queuedReply == "also check the tests", "a reply to a busy session is queued")
    var fds: [Int32] = [0, 0]
    socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
    let data = try! JSONSerialization.data(withJSONObject: [
        "source": "claude", "await_reply": true, "hook_pid": getpid(),
        "payload": ["session_id": "busy", "cwd": "/tmp/demo", "hook_event_name": "Stop"],
    ])
    store.apply(try! HookEnvelope.decode(data), reply: .awaitReply(HookConnection(fd: fds[0])))
    var buffer = [UInt8](repeating: 0, count: 64)
    let n = read(fds[1], &buffer, buffer.count)
    check(n > 0 && String(decoding: buffer[0..<n], as: UTF8.self) == "also check the tests", "the queued reply goes out when the turn ends")
    check(store.sessions["busy"]?.queuedReply == nil && store.sessions["busy"]?.status == .working, "and the session is working again")

    // A session removed by hand stays away through late events and comes back with new work.
    store.apply(envelope(["session_id": "gone", "hook_event_name": "Stop", "last_assistant_message": "done"]))
    store.dismiss(sessionId: "gone")
    store.apply(envelope(["session_id": "gone", "hook_event_name": "Notification", "message": "Claude is waiting for your input"]))
    check(store.sessions["gone"] == nil, "a removed session ignores late events")
    store.apply(envelope(["session_id": "gone", "hook_event_name": "UserPromptSubmit", "prompt": "again"]))
    check(store.sessions["gone"]?.status == .working, "a removed session returns with a new prompt")

    // A finished turn stays unread, even after Claude's idle prompt, until the session is opened.
    store.apply(envelope(["session_id": "unread", "hook_event_name": "UserPromptSubmit", "prompt": "go"]))
    store.apply(envelope(["session_id": "unread", "hook_event_name": "Stop", "last_assistant_message": "All done"]))
    store.apply(envelope(["session_id": "unread", "hook_event_name": "Notification", "notification_type": "idle_prompt",
                          "message": "Claude is waiting for your input"]))
    check(store.sessions["unread"]?.isUnseen == true && store.sessions["unread"]?.displayGroup == .finished,
          "an unread finish stays under Finished after the idle prompt")
    store.markSeen(sessionId: "unread", now: Date.now.addingTimeInterval(1))
    check(store.sessions["unread"]?.isQuiet == true, "once seen it counts as idle")

    // Sessions the hooks missed are found from their transcripts.
    let tdir = FileManager.default.temporaryDirectory.appendingPathComponent("tr-\(UUID().uuidString)/proj")
    try! FileManager.default.createDirectory(at: tdir, withIntermediateDirectories: true)
    let sid = UUID().uuidString.lowercased()
    let tfile = tdir.appendingPathComponent("\(sid).jsonl")
    let now = ISO8601DateFormatter().string(from: .now)
    try! """
    {"type":"user","cwd":"/tmp/found","gitBranch":"main","entrypoint":"cli","timestamp":"\(now)","message":{"role":"user","content":"fix it"}}
    {"type":"assistant","cwd":"/tmp/found","timestamp":"\(now)","message":{"stop_reason":"tool_use","content":[{"type":"tool_use"}]}}
    """.write(to: tfile, atomically: true, encoding: .utf8)
    var states = TranscriptScanner.recent(within: 60, root: tdir.deletingLastPathComponent())
    check(states.first?.phase == .working && states.first?.cwd == "/tmp/found", "a working transcript reads as working")
    store.applyDiscovery(states, processes: [ClaudeProcess(pid: 4242, cwd: "/tmp/found", tty: "ttys009")])
    check(store.sessions[sid]?.status == .working && store.sessions[sid]?.pid == 4242 && store.sessions[sid]?.discovered == true,
          "a session without hooks shows up, matched to its claude process")
    try! """
    {"type":"user","cwd":"/tmp/found","timestamp":"\(now)","message":{"role":"user","content":"fix it"}}
    {"type":"assistant","cwd":"/tmp/found","timestamp":"\(now)","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Fixed."}]}}
    """.write(to: tfile, atomically: true, encoding: .utf8)
    states = TranscriptScanner.recent(within: 60, root: tdir.deletingLastPathComponent())
    store.applyDiscovery(states, processes: [])
    check(store.sessions[sid]?.status == .done && store.sessions[sid]?.lastMessage == "Fixed." && store.sessions[sid]?.isUnseen == true,
          "its finished turn is picked up from the transcript")
    // Bookkeeping lines appended to an old transcript don't make it active.
    let staleId = UUID().uuidString.lowercased()
    try! """
    {"type":"user","cwd":"/tmp/stale","timestamp":"2026-01-01T10:00:00.000Z","message":{"role":"user","content":"old"}}
    {"type":"session-owner"}
    """.write(to: tdir.appendingPathComponent("\(staleId).jsonl"), atomically: true, encoding: .utf8)
    let fresh = TranscriptScanner.recent(within: 60, root: tdir.deletingLastPathComponent())
    check(!fresh.contains { $0.sessionId == staleId }, "an old transcript touched by bookkeeping isn't recent")
    // An old conversation with no live process is history, not a session.
    let old = TranscriptState(sessionId: UUID().uuidString, path: "/x", modified: .now.addingTimeInterval(-600), cwd: "/tmp/old", phase: .done)
    store.applyDiscovery([old], processes: [])
    check(store.sessions[old.sessionId] == nil, "a finished transcript without a process isn't added")
    // A session ended through its hook isn't brought back by its transcript.
    store.apply(envelope(["session_id": sid, "hook_event_name": "SessionEnd"]))
    store.applyDiscovery(states, processes: [ClaudeProcess(pid: 4242, cwd: "/tmp/found", tty: nil)])
    check(store.sessions[sid] == nil, "an ended session stays ended")
}

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
