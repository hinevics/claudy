import SwiftUI
import Combine

/// Текстовая полоска под нотчем в коллапс-режиме: показывает что Claude/Codex
/// сейчас делает (verb · tool · short arg · elapsed) + time-elapsed progress bar.
struct CollapsedActivityStrip: View {
    let session: SessionData

    @State private var now: Date = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var runningEvent: SessionEvent? {
        session.recentEvents.last(where: { $0.status == .running })
    }

    private var toolLabel: String? {
        runningEvent?.tool
    }

    private var argLabel: String? {
        guard let event = runningEvent else { return nil }
        guard let raw = event.description ?? event.tool else { return nil }
        return Self.shortenArg(tool: event.tool, raw: raw)
    }

    private var verb: String {
        switch session.task {
        case .compacting: return "Compacting"
        case .waiting:    return "Waiting"
        case .sleeping:   return "Sleeping"
        case .idle:       return "Idle"
        case .working:    return session.currentSpinnerVerb
        }
    }

    private var elapsedSeconds: TimeInterval {
        let anchor = runningEvent?.timestamp ?? session.promptSubmitTime ?? session.lastActivity
        return max(0, now.timeIntervalSince(anchor))
    }

    private var elapsedLabel: String {
        let total = Int(elapsedSeconds)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m \(String(format: "%02d", s))s" : "\(s)s"
    }

    /// 0..1 fill that fills over 60s, then stays at 1 (pulses via opacity).
    private var progress: Double {
        min(1.0, elapsedSeconds / 60.0)
    }

    private var progressColor: Color {
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
                ProcessingSpinner(color: progressColor)
                Text(verb)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                if let toolLabel {
                    Text("·")
                        .foregroundColor(.white.opacity(0.4))
                    Text(toolLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }
                if let argLabel {
                    Text("·")
                        .foregroundColor(.white.opacity(0.4))
                    Text(argLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if session.activeSubagentCount > 0 {
                    Text("·")
                        .foregroundColor(.white.opacity(0.4))
                    Text("+\(session.activeSubagentCount) subs")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                }
                Spacer(minLength: 6)
                Text(elapsedLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .monospacedDigit()
            }

            ProgressBar(progress: progress, color: progressColor, isMaxed: progress >= 1)
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

    private static func shortenArg(tool: String?, raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch tool {
        case "Read", "Write", "Edit":
            // description у нас "Reading /path/to/file" — отрежем глагол + basename
            let path = trimmed
                .replacingOccurrences(of: "Reading ", with: "")
                .replacingOccurrences(of: "Writing ", with: "")
                .replacingOccurrences(of: "Editing ", with: "")
            return (path as NSString).lastPathComponent
        case "Bash":
            // первый токен команды (npm test → npm test, до 28 симв)
            let oneLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
            return Self.cap(oneLine, length: 32)
        default:
            return Self.cap(trimmed, length: 28)
        }
    }

    private static func cap(_ s: String, length: Int) -> String {
        guard s.count > length else { return s }
        let i = s.index(s.startIndex, offsetBy: length)
        return String(s[..<i]) + "…"
    }
}

private struct ProgressBar: View {
    let progress: Double
    let color: Color
    let isMaxed: Bool

    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geo.size.width * CGFloat(progress)))
                    .opacity(isMaxed ? (pulse ? 0.55 : 1.0) : 1.0)
                    .animation(
                        isMaxed
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.4),
                        value: pulse
                    )
                    .animation(.easeOut(duration: 0.4), value: progress)
            }
            .onAppear { if isMaxed { pulse = true } }
            .onChange(of: isMaxed) { _, newValue in pulse = newValue }
        }
    }
}
