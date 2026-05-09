import AppKit

/// Borderless transparent panel for the activity strip pinned to the bottom of the screen.
///
/// The panel defaults to `ignoresMouseEvents = true` so its 480pt-tall transparent
/// canvas does not block clicks on apps below. When the user actively hovers the
/// bottom-edge hot zone we flip that off via `setMouseEventsEnabled(true)` so
/// strip rows become clickable, then flip back on hover-out.
final class BottomActivityPanel: NSPanel {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true

        level = .mainMenu + 3
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Toggle pass-through. Call only on hover-state transitions, never mid event
    /// dispatch. Pass-through (true) is the default and MUST be restored on
    /// hover-out — otherwise the panel silently swallows clicks across the
    /// entire bottom of the screen.
    func setMouseEventsEnabled(_ enabled: Bool) {
        let nextIgnores = !enabled
        guard ignoresMouseEvents != nextIgnores else { return }
        ignoresMouseEvents = nextIgnores
    }
}
