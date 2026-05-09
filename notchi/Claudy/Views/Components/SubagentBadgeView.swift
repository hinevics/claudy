import SwiftUI
import Combine

struct SubagentCountBadge: View {
    let count: Int

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(TerminalColors.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }

    private var label: String {
        count == 1 ? "1 subagent" : "\(count) subagents"
    }
}

struct SubagentListView: View {
    let subagents: [Subagent]

    @State private var now: Date = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(subagents) { subagent in
                SubagentRow(subagent: subagent, now: now)
            }
        }
        .onReceive(tick) { now = $0 }
    }
}

private struct SubagentRow: View {
    let subagent: Subagent
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(TerminalColors.amber)
                .frame(width: 4, height: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(subagent.displayDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let type = subagent.subagentType {
                    Text(type)
                        .font(.system(size: 9))
                        .foregroundColor(TerminalColors.dimmedText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(elapsedLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(TerminalColors.secondaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private var elapsedLabel: String {
        let endpoint = subagent.endedAt ?? now
        let seconds = max(0, endpoint.timeIntervalSince(subagent.startedAt))
        return Subagent.formatElapsed(seconds)
    }
}
