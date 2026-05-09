import Foundation

nonisolated struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let cwd: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let subagentCount: Int
    let provider: String

    var providerEnum: AgentProvider? {
        AgentProvider(rawValue: provider)
    }

    var projectBasename: String {
        (cwd as NSString).lastPathComponent
    }
}
