import SwiftUI
import IslandCore

/// A session's subagents: a summary line, then one line per agent (running first).
struct SubagentList: View {
    let subagents: [Subagent]
    let now: Date
    private static let maxLines = 4

    var body: some View {
        let running = subagents.filter { $0.state == .running }
        let ordered = running + subagents.filter { $0.state != .running }.reversed()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(subagents.prefix(10)) { agent in
                        Circle().fill(color(agent.state)).frame(width: 5, height: 5)
                    }
                }
                Text(headline(running: running.count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Crystal.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            ForEach(ordered.prefix(Self.maxLines)) { agent in
                line(agent)
            }
            if ordered.count > Self.maxLines {
                Text("+\(ordered.count - Self.maxLines) more")
                    .font(.system(size: 12))
                    .foregroundStyle(Crystal.tertiary)
            }
        }
    }

    private func line(_ agent: Subagent) -> some View {
        HStack(spacing: 8) {
            Group {
                switch agent.state {
                case .running: Equalizer().scaleEffect(0.7)
                case .done: Glyph(symbol: "checkmark", color: Crystal.amethyst, size: 11, weight: .bold)
                case .stopped: Glyph(symbol: "stop.fill", color: Crystal.tertiary, size: 10)
                }
            }
            .frame(width: 12, height: 12)
            Text(agent.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(agent.state == .running ? Crystal.body : Crystal.secondary)
                .layoutPriority(1)
            Text(detail(agent))
                .font(.system(size: 12))
                .foregroundStyle(agent.state == .done ? Crystal.amethystText : Crystal.tertiary)
            Spacer(minLength: 6)
            Text(Clock.format((agent.finishedAt ?? now).timeIntervalSince(agent.startedAt)))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(agent.state == .running ? Crystal.body : Crystal.tertiary)
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private func headline(running: Int) -> String {
        let total = subagents.count
        let noun = total == 1 ? "agent" : "agents"
        if running == total { return "\(total) \(noun) running" }
        if running == 0 { return "\(total) \(noun) finished" }
        return "\(running) of \(total) \(noun) running"
    }

    private func detail(_ agent: Subagent) -> String {
        switch agent.state {
        case .running: agent.activity ?? "Starting…"
        case .done: agent.summary ?? "Done"
        case .stopped: "Stopped"
        }
    }

    private func color(_ state: Subagent.State) -> Color {
        switch state {
        case .running: Crystal.emerald
        case .done: Crystal.amethyst
        case .stopped: Crystal.tertiary
        }
    }
}
