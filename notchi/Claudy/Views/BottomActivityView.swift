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

    @State private var isHovering: Bool = false
    @State private var collapseTask: Task<Void, Never>?

    private var sessionFilter: BottomPanelSessionFilter {
        BottomPanelSessionFilter(rawValue: sessionFilterRaw) ?? BottomPanelSettingsKeys.defaultSessionFilter
    }

    private var sessionStore: SessionStore {
        stateMachine.sessionStore
    }

    /// All sessions eligible for the bottom panel, respecting sessionFilter but NOT capped by rowLimit.
    /// rowLimit is applied only to the expanded per-session list, not to the aggregate count.
    private var eligibleSessions: [SessionData] {
        guard sessionFilter != .none else { return [] }
        let candidates = sessionStore.sortedSessions.filter(Self.isStripEligible)
        switch sessionFilter {
        case .none:       return []
        case .activeOnly: return candidates.filter { Self.isActive($0) }
        case .all:        return candidates
        }
    }

    /// Sessions to render in the expanded (per-session) list. Capped by rowLimit.
    private var expandedSessions: [SessionData] {
        let cap = max(BottomPanelSettingsKeys.rowLimitRange.lowerBound,
                      min(rowLimit, BottomPanelSettingsKeys.rowLimitRange.upperBound))
        return Array(eligibleSessions.prefix(cap))
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
        let sessions = eligibleSessions
        let useAggregate = sessions.count >= 2 && !isHovering

        return VStack(spacing: 6) {
            Spacer()
            content(sessions: sessions, useAggregate: useAggregate)
            if !sessions.isEmpty {
                Spacer().frame(height: 12)
            }
        }
        .opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: useAggregate)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sessions.map(\.id))
        .onChange(of: sessions.count) { _, newCount in
            if newCount < 2 { isHovering = false }
        }
    }

    @ViewBuilder
    private func content(sessions: [SessionData], useAggregate: Bool) -> some View {
        if useAggregate {
            AggregateActivityStrip(sessions: sessions)
                .frame(width: 360)
                .onHover(perform: handleHover)
                .transition(.opacity)
        } else {
            expandedStack(sessions: sessions)
        }
    }

    @ViewBuilder
    private func expandedStack(sessions: [SessionData]) -> some View {
        let stripWidth: CGFloat = 360
        VStack(spacing: 6) {
            ForEach(expandedSessions, id: \.id) { session in
                CollapsedActivityStrip(session: session)
                    .frame(width: stripWidth)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        // WHY: while expanded for 2+ sessions, keep tracking hover so we can collapse
        // back when the cursor leaves the whole stack (with a small grace period).
        .onHover { hovering in
            if sessions.count >= 2 {
                handleHover(hovering)
            }
        }
    }

    private func handleHover(_ hovering: Bool) {
        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
            if !isHovering { isHovering = true }
        } else {
            // WHY: brief overshoots crossing strip gaps shouldn't collapse the stack.
            collapseTask?.cancel()
            collapseTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                isHovering = false
            }
        }
    }
}
