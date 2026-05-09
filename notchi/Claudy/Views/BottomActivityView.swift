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

    /// Hover signal driven by BottomEdgeHoverMonitor (global mouse position
    /// near screen bottom edge). Replaces the previous SwiftUI .onHover
    /// plumbing — the panel is now ignoresMouseEvents=true and much taller,
    /// so SwiftUI hover wouldn't fire reliably anyway.
    @EnvironmentObject private var hoverMonitor: BottomEdgeHoverMonitor

    private var isHovering: Bool { hoverMonitor.isHovering }

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
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                if useAggregate {
                    AggregateActivityStrip(sessions: sessions)
                        .frame(width: 360)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeInOut(duration: 0.18).delay(0.05)),
                            removal: .opacity.animation(.easeInOut(duration: 0.12))
                        ))
                } else if !sessions.isEmpty {
                    expandedStack(sessions: sessions)
                        .scaleEffect(isHovering ? 1.0 : 0.92, anchor: .bottom)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.92, anchor: .bottom)),
                            removal: .move(edge: .bottom)
                                .combined(with: .opacity)
                        ))
                }
            }
            if !sessions.isEmpty {
                Spacer().frame(height: 12)
            }
        }
        .opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: useAggregate)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sessions.map(\.id))
    }

    @ViewBuilder
    private func expandedStack(sessions: [SessionData]) -> some View {
        let stripWidth: CGFloat = 360
        VStack(spacing: 6) {
            ForEach(expandedSessions, id: \.id) { session in
                CollapsedActivityStrip(session: session)
                    .frame(width: stripWidth)
            }
        }
    }
}
