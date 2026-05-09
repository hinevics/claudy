import SwiftUI
import Combine

/// Single-row aggregate that replaces the stacked CollapsedActivityStrip list when 2+
/// sessions are active. Visually matches CollapsedActivityStrip (font, padding, pill
/// background, divider) so it reads as "one of them" rather than a separate widget.
struct AggregateActivityStrip: View {
    let sessions: [SessionData]

    @State private var now: Date = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Rank by task priority (working > waiting > compacting > idle/sleeping),
    /// tie-break by most recent lastActivity.
    private var anchorSession: SessionData? {
        sessions.max(by: { lhs, rhs in
            let lp = Self.taskPriority(lhs.task)
            let rp = Self.taskPriority(rhs.task)
            if lp != rp { return lp < rp }
            return lhs.lastActivity < rhs.lastActivity
        })
    }

    private static func taskPriority(_ task: NotchiTask) -> Int {
        switch task {
        case .working:    return 4
        case .waiting:    return 3
        case .compacting: return 2
        case .idle:       return 1
        case .sleeping:   return 0
        }
    }

    private var totalActiveSubagents: Int {
        sessions.reduce(0) { $0 + $1.activeSubagentCount }
    }

    private var anchorRunningEvent: SessionEvent? {
        anchorSession?.recentEvents.last(where: { $0.status == .running })
    }

    private var elapsedSeconds: TimeInterval {
        guard let anchor = anchorSession else { return 0 }
        let t = anchorRunningEvent?.timestamp ?? anchor.promptSubmitTime ?? anchor.lastActivity
        return max(0, now.timeIntervalSince(t))
    }

    private var elapsedLabel: String {
        let total = Int(elapsedSeconds)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m \(String(format: "%02d", s))s" : "\(s)s"
    }

    private var progress: Double {
        min(1.0, elapsedSeconds / 60.0)
    }

    private var dotColor: Color {
        switch elapsedSeconds {
        case ..<10:  return Color.green.opacity(0.8)
        case ..<30:  return TerminalColors.claudeOrange
        case ..<60:  return Color.orange
        default:     return Color.red.opacity(0.85)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ProcessingSpinner(color: dotColor)
                Text("\(sessions.count) sessions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))

                if totalActiveSubagents > 0 {
                    Text("·")
                        .foregroundColor(.white.opacity(0.4))
                    Text("+\(totalActiveSubagents) subs")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                }

                Spacer(minLength: 6)

                Text("·")
                    .foregroundColor(.white.opacity(0.4))
                Text(elapsedLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .monospacedDigit()
            }

            // WHY: keep the same vertical rhythm as CollapsedActivityStrip so swapping
            // between aggregate and stacked layouts doesn't visibly change row height.
            Capsule()
                .fill(dotColor.opacity(0.35))
                .frame(height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    GeometryReader { geo in
                        Capsule()
                            .fill(dotColor)
                            .frame(width: max(2, geo.size.width * CGFloat(progress)))
                    }
                )
                .frame(height: 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
        .onReceive(tick) { now = $0 }
    }
}
