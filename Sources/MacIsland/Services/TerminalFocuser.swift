import AppKit
import IslandCore
import os
import IslandCore

private let log = Logger(subsystem: "com.fufic123.macisland", category: "focus")

/// Brings the terminal running a session to the front, down to the exact tab when possible.
@MainActor
enum TerminalFocuser {
    static func focus(_ session: AgentSession) {
        log.info("focus \(session.projectName, privacy: .public) term=\(session.termProgram ?? "-", privacy: .public) tty=\(session.tty ?? "-", privacy: .public) pid=\(session.pid ?? -1)")
        // The tty arrives over the socket, so accept only the "ttysNNN" shape and pass it
        // to AppleScript as an argument rather than splicing it into the source.
        if let tty = session.tty,
           tty.range(of: "^ttys?[0-9]{1,4}$", options: .regularExpression) != nil,
           let script = tabScript(termProgram: session.termProgram) {
            runAppleScript(script, argument: "/dev/\(tty)") { ok in
                if !ok { activateOwningApp(of: session) }
            }
        } else {
            activateOwningApp(of: session)
        }
    }

    /// Terminal.app and iTerm2 can select a tab by its tty via AppleScript; the tty is `item 1 of argv`.
    private static func tabScript(termProgram: String?) -> String? {
        switch termProgram {
        case "Apple_Terminal":
            return """
            on run argv
            set targetTty to item 1 of argv
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is targetTty then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
            error "tab not found"
            end run
            """
        case "iTerm.app":
            return """
            on run argv
            set targetTty to item 1 of argv
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is targetTty then
                                select w
                                select t
                                select s
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            error "session not found"
            end run
            """
        default:
            return nil
        }
    }

    /// Fallback for any terminal/IDE: walk up from Claude's pid to the GUI app hosting it.
    private static func activateOwningApp(of session: AgentSession) {
        guard var pid = session.pid else { return }
        for _ in 0..<20 {
            if let app = NSRunningApplication(processIdentifier: pid),
               app.activationPolicy == .regular,
               let url = app.bundleURL {
                // openApplication works from a background app, unlike NSRunningApplication.activate.
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                // VS Code and its forks (Cursor, Windsurf) all report TERM_PROGRAM=vscode; opening the
                // project folder with the app raises the window that has it open instead of
                // whichever window happens to be frontmost.
                if session.termProgram == "vscode", let cwd = session.cwd {
                    NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: url, configuration: config)
                } else {
                    NSWorkspace.shared.openApplication(at: url, configuration: config)
                }
                log.info("activated \(app.bundleIdentifier ?? "?", privacy: .public)")
                return
            }
            guard let parent = parentPid(of: pid) else { break }
            pid = parent
        }
        log.error("No GUI app found for session \(session.id, privacy: .public)")
    }

    private static func parentPid(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 1 ? parent : nil
    }

    /// Runs osascript off the main thread; Automation permission is requested on first use.
    private static func runAppleScript(_ source: String, argument: String, completion: @escaping @MainActor (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source, argument]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { p in
            let ok = p.terminationStatus == 0
            Task { @MainActor in completion(ok) }
        }
        do {
            try process.run()
        } catch {
            completion(false)
        }
    }
}
