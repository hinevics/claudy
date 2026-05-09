import SwiftUI

/// Hosted in BottomActivityPanel — shows collapsed activity strips pinned to the
/// bottom-center of the screen for running Claude/Codex sessions.
struct BottomActivityView: View {
    var stateMachine: NotchiStateMachine = .shared

    @AppStorage(BottomPanelSettingsKeys.sessionFilter)
    private var sessionFilterRaw: String = BottomPanelSettingsKeys.defaultSessionFilter.rawValue

    @AppStorage(BottomPanelSettingsKeys.rowLimit)
    private var rowLimit: Int = BottomPanelSettingsKeys.defaultRowLimit

    @AppStorage(BottomPanelSettingsKeys.opacity)
    private var opacity: Double = BottomPanelSettingsKeys.defaultOpacity

    private var sessionFilter: BottomPanelSessionFilter {
        BottomPanelSessionFilter(rawValue: sessionFilterRaw) ?? BottomPanelSettingsKeys.defaultSessionFilter
    }

    private var sessionStore: SessionStore {
        stateMachine.sessionStore
    }

    private var visibleSessions: [SessionData] {
        guard sessionFilter != .none else { return [] }
        let candidates = sessionStore.sortedSessions.filter(Self.isStripEligible)
        let filtered: [SessionData]
        switch sessionFilter {
        case .none:
            filtered = []
        case .activeOnly:
            filtered = candidates.filter { Self.isActive($0) }
        case .all:
            filtered = candidates
        }
        let cap = max(BottomPanelSettingsKeys.rowLimitRange.lowerBound,
                      min(rowLimit, BottomPanelSettingsKeys.rowLimitRange.upperBound))
        return Array(filtered.prefix(cap))
    }

    private static func isStripEligible(_ session: SessionData) -> Bool {
        switch session.task {
        case .working, .compacting, .waiting: return true
        case .idle, .sleeping:                return false
        }
    }

    private static func isActive(_ session: SessionData) -> Bool {
        switch session.task {
        case .working, .compacting, .waiting: return true
        case .idle, .sleeping:                return false
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            ForEach(visibleSessions, id: \.id) { session in
                CollapsedActivityStrip(session: session)
                    .frame(width: 360)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
            if !visibleSessions.isEmpty {
                Spacer().frame(height: 12)
            }
        }
        .opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: visibleSessions.map(\.id))
    }
}
