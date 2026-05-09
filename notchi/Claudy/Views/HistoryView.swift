import SwiftUI
import AppKit

enum ActivityTab: Hashable {
    case sessions
    case history
}

struct HistoryView: View {
    @ObservedObject var store: SessionHistoryStore

    var body: some View {
        let entries = store.todaysEntries()

        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TerminalColors.secondaryText)
                .padding(.top, 8)
                .padding(.bottom, 8)

            if entries.isEmpty {
                Spacer(minLength: 0)
                Text("No completed sessions yet today.")
                    .font(.system(size: 12))
                    .foregroundColor(TerminalColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(entries) { entry in
                            HistoryRowView(entry: entry) {
                                NSWorkspace.shared.open(URL(fileURLWithPath: entry.cwd))
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
}

private struct HistoryRowView: View {
    let entry: HistoryEntry
    let onOpen: () -> Void

    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var timeRange: String {
        let start = Self.timeFormatter.string(from: entry.startedAt)
        let end = Self.timeFormatter.string(from: entry.endedAt)
        return "\(start) -> \(end)"
    }

    private var durationText: String {
        let total = max(0, entry.durationSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.projectBasename)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(TerminalColors.primaryText)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer()

                    Text(timeRange)
                        .font(.system(size: 10))
                        .foregroundColor(TerminalColors.dimmedText)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(durationText)
                        .font(.system(size: 10))
                        .foregroundColor(TerminalColors.dimmedText)

                    if entry.subagentCount > 0 {
                        Text("- \(entry.subagentCount) subs")
                            .font(.system(size: 10))
                            .foregroundColor(TerminalColors.dimmedText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(isHovered ? TerminalColors.hoverBackground : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
