import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.ruban.notchi", category: "history")

@MainActor
final class SessionHistoryStore: ObservableObject {
    static let shared = SessionHistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private static let retentionInterval: TimeInterval = 60 * 60 * 24 * 30

    private init() {
        let baseURL: URL = {
            if let appSupport = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) {
                return appSupport
            }
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        }()

        self.directoryURL = baseURL.appendingPathComponent("Claudy", isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent("history.json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    func record(_ session: SessionData) {
        let endedAt = Date()
        let startedAt = session.sessionStartTime
        let duration = max(0, Int(endedAt.timeIntervalSince(startedAt)))

        if entries.contains(where: { $0.id == session.id }) {
            logger.debug("Skipping duplicate history record for session \(session.id, privacy: .public)")
            return
        }

        let entry = HistoryEntry(
            id: session.id,
            cwd: session.cwd,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: duration,
            subagentCount: session.subagents.count,
            provider: session.provider.rawValue
        )

        var next = entries
        next.append(entry)
        next = Self.trimRetention(next)
        next.sort { $0.endedAt > $1.endedAt }
        entries = next
        save()
        logger.info("Recorded history entry for session \(session.id, privacy: .public) duration=\(duration)s")
    }

    func todaysEntries() -> [HistoryEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDateInToday($0.endedAt) }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode([HistoryEntry].self, from: data)
            let trimmed = Self.trimRetention(decoded).sorted { $0.endedAt > $1.endedAt }
            entries = trimmed
        } catch {
            logger.error("Failed to load history.json: \(error.localizedDescription, privacy: .public)")
            entries = []
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save history.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func trimRetention(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        return entries.filter { $0.endedAt >= cutoff }
    }
}
