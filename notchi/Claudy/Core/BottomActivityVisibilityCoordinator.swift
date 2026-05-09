import AppKit

/// Hides/shows the bottom activity panel based on user settings and full-screen state.
///
/// Full-screen detection: enumerate on-screen windows via
/// `CGWindowListCopyWindowInfo` and look for any window at the normal layer (0),
/// owned by another process, whose bounds match the target screen's frame. That
/// matches a full-screen app's content window. We re-evaluate on
/// active-space-did-change since macOS moves full-screen apps to their own
/// space.
@MainActor
final class BottomActivityVisibilityCoordinator {
    private weak var panel: BottomActivityPanel?
    private let resolveScreen: () -> NSScreen?
    private var defaultsObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var screenParamsObserver: NSObjectProtocol?
    private var isStarted = false

    init(panel: BottomActivityPanel, resolveScreen: @escaping () -> NSScreen?) {
        self.panel = panel
        self.resolveScreen = resolveScreen
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyVisibility()
            }
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyVisibility()
            }
        }

        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyVisibility()
            }
        }

        applyVisibility()
    }

    func stop() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        if let screenParamsObserver {
            NotificationCenter.default.removeObserver(screenParamsObserver)
        }
        defaultsObserver = nil
        spaceObserver = nil
        screenParamsObserver = nil
        isStarted = false
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        if let screenParamsObserver {
            NotificationCenter.default.removeObserver(screenParamsObserver)
        }
    }

    private func applyVisibility() {
        guard let panel else { return }

        let filterRaw = UserDefaults.standard.string(forKey: BottomPanelSettingsKeys.sessionFilter)
            ?? BottomPanelSettingsKeys.defaultSessionFilter.rawValue
        let filter = BottomPanelSessionFilter(rawValue: filterRaw) ?? BottomPanelSettingsKeys.defaultSessionFilter

        let hideOnFullScreen: Bool = {
            guard UserDefaults.standard.object(forKey: BottomPanelSettingsKeys.hideOnFullScreen) != nil else {
                return BottomPanelSettingsKeys.defaultHideOnFullScreen
            }
            return UserDefaults.standard.bool(forKey: BottomPanelSettingsKeys.hideOnFullScreen)
        }()

        var shouldHide = false
        if filter == .none {
            shouldHide = true
        } else if hideOnFullScreen, screenHasFullScreenApp() {
            shouldHide = true
        }

        if shouldHide {
            if panel.isVisible {
                panel.orderOut(nil)
            }
        } else {
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
    }

    private func screenHasFullScreenApp() -> Bool {
        guard let screen = resolveScreen() ?? NSScreen.main else { return false }
        let screenFrame = screen.frame
        let ownPid = ProcessInfo.processInfo.processIdentifier

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ownPid,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }

            // CGWindow coordinates use top-left origin in the global display
            // space; NSScreen uses bottom-left. Convert by flipping against the
            // primary screen height for comparison.
            guard let primary = NSScreen.screens.first else { continue }
            let primaryHeight = primary.frame.height
            let flippedY = primaryHeight - bounds.origin.y - bounds.height
            let nsBounds = CGRect(x: bounds.origin.x, y: flippedY, width: bounds.width, height: bounds.height)

            if abs(nsBounds.origin.x - screenFrame.origin.x) < 1.0,
               abs(nsBounds.origin.y - screenFrame.origin.y) < 1.0,
               abs(nsBounds.width - screenFrame.width) < 1.0,
               abs(nsBounds.height - screenFrame.height) < 1.0 {
                return true
            }
        }

        return false
    }
}
