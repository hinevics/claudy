import SwiftUI

/// Hosted in BottomActivityPanel — shows collapsed activity strips pinned to the
/// bottom-center of the screen for running Claude/Codex sessions.
struct BottomActivityView: View {
    var stateMachine: NotchiStateMachine = .shared

    /// Called whenever the panel should switch between pass-through (false)
    /// and click-accepting (true). Driven by the hover monitor combined with
    /// whether any strips are currently rendered. AppDelegate wires this to
    /// `BottomActivityPanel.setMouseEventsEnabled(_:)`.
    var onMouseInteractivityChange: ((Bool) -> Void)? = nil

    /// Called whenever the desired panel height changes. AppDelegate resizes
    /// the NSPanel accordingly so we never sit on a 480pt invisible window
    /// blocking events for apps below.
    var onContentHeightChange: ((CGFloat) -> Void)? = nil

    @AppStorage(BottomPanelSettingsKeys.enabled)
    private var enabled: Bool = BottomPanelSettingsKeys.defaultEnabled

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
        guard enabled else { return [] }
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
                    let multiSession = sessions.count >= 2
                    expandedStack(sessions: sessions)
                        .transition(multiSession
                            ? .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                              )
                            : .identity)
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
        // Drive panel pass-through. Interactive only while the hot-zone is
        // hovered AND there is at least one strip to click. When the stack
        // collapses (no sessions, or hover-out) we MUST flip back to
        // pass-through so the transparent 480pt panel doesn't swallow clicks
        // for apps below.
        .onChange(of: shouldAcceptMouseEvents) { _, newValue in
            onMouseInteractivityChange?(newValue)
        }
        .onAppear {
            onMouseInteractivityChange?(shouldAcceptMouseEvents)
            onContentHeightChange?(desiredPanelHeight)
        }
        .onChange(of: desiredPanelHeight) { _, newValue in
            onContentHeightChange?(newValue)
        }
    }

    private var shouldAcceptMouseEvents: Bool {
        isHovering && !eligibleSessions.isEmpty
    }

    /// Pixel-precise height the NSPanel needs to host the current content.
    /// Kept tight (one strip + bottom padding) by default so the transparent
    /// panel doesn't cover the bottom of the screen and swallow events.
    private var desiredPanelHeight: CGFloat {
        let count = eligibleSessions.count
        guard count > 0 else { return 4 }
        let stripHeight: CGFloat = 46
        let spacing: CGFloat = 6
        let bottomPadding: CGFloat = 12
        let useAggregate = count >= 2 && !isHovering
        if useAggregate || count == 1 {
            return stripHeight + bottomPadding
        }
        let cap = max(BottomPanelSettingsKeys.rowLimitRange.lowerBound,
                      min(rowLimit, BottomPanelSettingsKeys.rowLimitRange.upperBound))
        let visible = min(count, cap)
        return CGFloat(visible) * stripHeight + CGFloat(max(visible - 1, 0)) * spacing + bottomPadding
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
