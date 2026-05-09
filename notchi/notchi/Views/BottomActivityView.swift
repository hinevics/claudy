import SwiftUI

/// Hosted in BottomActivityPanel — shows the collapsed activity strip pinned to the
/// bottom-center of the screen whenever there's an active Claude/Codex session running.
struct BottomActivityView: View {
    var stateMachine: NotchiStateMachine = .shared

    private var sessionStore: SessionStore {
        stateMachine.sessionStore
    }

    private var activeSession: SessionData? {
        sessionStore.effectiveSession
    }

    private var shouldShow: Bool {
        guard let activeSession else { return false }
        switch activeSession.task {
        case .working, .compacting, .waiting: return true
        case .idle, .sleeping:                return false
        }
    }

    var body: some View {
        VStack {
            Spacer()
            if shouldShow, let activeSession {
                CollapsedActivityStrip(session: activeSession)
                    .frame(width: 360)
                    .padding(.bottom, 18)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: shouldShow)
    }
}
