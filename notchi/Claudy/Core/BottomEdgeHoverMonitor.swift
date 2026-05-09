import AppKit
import Combine

/// Tracks whether the user's cursor is inside the "hot zone" near the bottom
/// edge of the panel's screen. Drives the dock-like reveal of the bottom
/// activity stack: aggregate row pinned at the screen edge, expanded list
/// slides up when cursor approaches.
///
/// We use both global and local NSEvent monitors so the hot zone reacts no
/// matter which app currently owns key focus. ignoresMouseEvents on the panel
/// means the local monitor only fires when the cursor is over our own
/// non-interactive panel content (rare given pass-through), but we keep it
/// for symmetry / resilience.
@MainActor
final class BottomEdgeHoverMonitor: ObservableObject {
    @Published private(set) var isHovering: Bool = false

    /// Debounce window for hover-out — prevents flicker when the cursor
    /// momentarily overshoots strip gaps.
    private let collapseDelayNanos: UInt64 = 100_000_000

    /// Resolver returning the panel's CURRENT frame (the visible strip area
    /// in screen coordinates). Hover is true while the cursor is inside
    /// that rectangle — so the trigger area is always exactly what the user
    /// can see, regardless of where the panel sits or how tall it is.
    private var resolvePanelFrame: (() -> NSRect?)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var collapseTask: Task<Void, Never>?
    private var isStarted = false

    func start(resolvePanelFrame: @escaping () -> NSRect?) {
        guard !isStarted else { return }
        isStarted = true
        self.resolvePanelFrame = resolvePanelFrame

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            // Global monitors deliver events on the main thread already, but
            // hop onto the main actor explicitly to satisfy isolation.
            Task { @MainActor [weak self] in
                self?.evaluate()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.evaluate()
            }
            return event
        }

        evaluate()
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        collapseTask?.cancel()
        collapseTask = nil
        resolvePanelFrame = nil
        isStarted = false
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func evaluate() {
        guard let frame = resolvePanelFrame?() else { return }
        let location = NSEvent.mouseLocation

        let shouldHover = frame.contains(location)

        if shouldHover {
            collapseTask?.cancel()
            collapseTask = nil
            if !isHovering {
                isHovering = true
                HapticService.shared.playHoverClick()
            }
        } else if isHovering {
            collapseTask?.cancel()
            let delay = collapseDelayNanos
            collapseTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { return }
                self?.isHovering = false
            }
        }
    }
}
