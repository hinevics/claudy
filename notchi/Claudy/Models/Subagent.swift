import Foundation

nonisolated struct Subagent: Identifiable, Sendable {
    let id: String
    let toolUseId: String?
    let description: String
    let subagentType: String?
    let startedAt: Date
    var endedAt: Date?

    var isActive: Bool {
        endedAt == nil
    }

    var elapsed: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }

    var displayDescription: String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 40 else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 40)
        return String(trimmed[..<index]) + "..."
    }

    static func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
