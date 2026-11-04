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
print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
