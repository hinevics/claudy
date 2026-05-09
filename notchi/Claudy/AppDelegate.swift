import AppKit
import os.log
import Sparkle
import SwiftUI

private let logger = Logger(subsystem: "com.ruban.notchi", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var notchPanel: NotchPanel?
    private var bottomActivityPanel: BottomActivityPanel?
    private var bottomActivityVisibilityCoordinator: BottomActivityVisibilityCoordinator?
    private var bottomEdgeHoverMonitor: BottomEdgeHoverMonitor?
    private let windowHeight: CGFloat = 500
    // Initial height before SwiftUI reports its content size. Real height is
    // driven by BottomActivityView.onContentHeightChange so the transparent
    // panel never grows past what's actually visible — otherwise it sits over
    // the bottom half of the screen and swallows clicks for apps below.
    private let bottomActivityHeight: CGFloat = 60
    private let integrationCoordinator = IntegrationCoordinator.shared

    private var updaterStarted = false
    private var temporarilyRegularForUpdateSession = false
    private lazy var standardUserDriver = SPUStandardUserDriver(
        hostBundle: .main,
        delegate: self
    )
    private lazy var updateUserDriver = NotchiUpdateUserDriver(
        standardUserDriver: standardUserDriver,
        shouldHandleUpdaterErrorsInline: { UpdateManager.shared.shouldHandleUpdaterErrorInline },
        didFinishCustomSession: { [weak self] in
            UpdateManager.shared.finishUpdateSession()
            self?.restoreAccessoryModeIfNeeded()
        }
    )
    private lazy var updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: updateUserDriver,
        delegate: self
    )
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }

        NSApplication.shared.setActivationPolicy(.accessory)
        integrationCoordinator.prepareForLaunch()
        setupNotchWindow()
        setupBottomActivityWindow()
        observeScreenChanges()
        observeWakeNotifications()
        startHookServices()
        startUsageService()
        startUpdater()
    }

    private func startHookServices() {
        integrationCoordinator.installHooksIfNeeded()
        integrationCoordinator.start { event in
            NotchiStateMachine.shared.handleEvent(event)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        integrationCoordinator.stop()
        ClaudeUsageService.shared.stopPolling()
        bottomEdgeHoverMonitor?.stop()
        bottomActivityVisibilityCoordinator?.stop()
    }

    @MainActor private func setupNotchWindow() {
        ScreenSelector.shared.refreshScreens()
        guard let screen = ScreenSelector.shared.selectedScreen else { return }
        NotchPanelManager.shared.updateGeometry(for: screen)

        let panel = NotchPanel(frame: windowFrame(for: screen))

        let contentView = NotchContentView()
        let hostingView = NSHostingView(rootView: contentView)

        let hitTestView = NotchHitTestView()
        hitTestView.panelManager = NotchPanelManager.shared
        hitTestView.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: hitTestView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: hitTestView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: hitTestView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: hitTestView.trailingAnchor),
        ])

        panel.contentView = hitTestView
        panel.orderFrontRegardless()

        self.notchPanel = panel
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionWindow),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func observeWakeNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func repositionWindow() {
        MainActor.assumeIsolated {
            guard let panel = notchPanel else { return }
            ScreenSelector.shared.refreshScreens()
            guard let screen = ScreenSelector.shared.selectedScreen else { return }

            NotchPanelManager.shared.updateGeometry(for: screen)
            panel.setFrame(windowFrame(for: screen), display: true)
            bottomActivityPanel?.setFrame(bottomActivityFrame(for: screen), display: true)
        }
    }

    @MainActor private func setupBottomActivityWindow() {
        guard let screen = ScreenSelector.shared.selectedScreen else { return }
        let panel = BottomActivityPanel(frame: bottomActivityFrame(for: screen))

        let hoverMonitor = BottomEdgeHoverMonitor()
        let rootView = BottomActivityView(
            onMouseInteractivityChange: { [weak panel] enabled in
                // Flip pass-through only on hover-state transitions. Default
                // (and post-hover) MUST be pass-through.
                panel?.setMouseEventsEnabled(enabled)
            },
            onContentHeightChange: { [weak self] height in
                self?.resizeBottomActivityPanel(toHeight: height)
            }
        ).environmentObject(hoverMonitor)
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        panel.contentView = container
        panel.orderFrontRegardless()
        self.bottomActivityPanel = panel

        let coordinator = BottomActivityVisibilityCoordinator(panel: panel) { [weak self] in
            self?.bottomActivityPanel?.screen ?? ScreenSelector.shared.selectedScreen
        }
        coordinator.start()
        self.bottomActivityVisibilityCoordinator = coordinator

        hoverMonitor.start { [weak self] in
            self?.bottomActivityPanel?.screen ?? ScreenSelector.shared.selectedScreen
        }
        self.bottomEdgeHoverMonitor = hoverMonitor
    }

    @MainActor private func resizeBottomActivityPanel(toHeight height: CGFloat) {
        guard let panel = bottomActivityPanel else { return }
        let screen = panel.screen ?? ScreenSelector.shared.selectedScreen
        guard let visible = screen?.visibleFrame else { return }
        let clamped = max(4, min(height, 480))
        let frame = NSRect(
            x: visible.origin.x,
            y: visible.origin.y,
            width: visible.width,
            height: clamped
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func bottomActivityFrame(for screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        return NSRect(
            x: visibleFrame.origin.x,
            y: visibleFrame.origin.y,
            width: visibleFrame.width,
            height: bottomActivityHeight
        )
    }

    @objc private func handleSystemWake() {
        MainActor.assumeIsolated {
            logger.info("System woke, restarting Claude usage polling")
            ClaudeUsageService.shared.startPolling(afterSystemWake: true)
        }
    }

    private func windowFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        return NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )
    }

    @MainActor private func startUsageService() {
        ClaudeUsageService.shared.startPolling()
    }

    private func startUpdater() {
        guard !updaterStarted else { return }

        UpdateManager.shared.setUpdater(updater)
        do {
            try updater.start()
        } catch {
            logger.error("Failed to start Sparkle updater: \(error.localizedDescription, privacy: .public)")
            return
        }
        updaterStarted = true
    }

    private func presentUpdateUIIfNeeded() {
        guard NSApp.activationPolicy() != .regular else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        temporarilyRegularForUpdateSession = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreAccessoryModeIfNeeded() {
        guard temporarilyRegularForUpdateSession else { return }
        temporarilyRegularForUpdateSession = false
        NSApp.setActivationPolicy(.accessory)
    }

}

// MARK: - SPUUpdaterDelegate

extension AppDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        UpdateManager.shared.updateFound(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        UpdateManager.shared.noUpdateFound()
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMakeChoice choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        UpdateManager.shared.userMadeChoice(
            choice,
            stage: state.stage,
            version: updateItem.displayVersionString
        )
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        UpdateManager.shared.downloadStarted()
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        UpdateManager.shared.readyToInstall(version: item.displayVersionString)
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        UpdateManager.shared.readyToInstall(version: item.displayVersionString)
        return false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError

        if UpdateManager.shouldIgnoreAbortError(nsError) {
            return
        }

        logSparkleAbort(nsError)
        UpdateManager.shared.updateError()
    }

    private func logSparkleAbort(_ error: NSError) {
        let failureReason = error.localizedFailureReason ?? "nil"
        let recoverySuggestion = error.localizedRecoverySuggestion ?? "nil"
        let noUpdateReason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.stringValue ?? "nil"
        let latestVersion = (error.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem)?.displayVersionString ?? "nil"

        logger.error(
            """
            Sparkle updater aborted. domain=\(error.domain, privacy: .public) code=\(error.code, privacy: .public) description=\(error.localizedDescription, privacy: .public) failureReason=\(failureReason, privacy: .public) recoverySuggestion=\(recoverySuggestion, privacy: .public) noUpdateReason=\(noUpdateReason, privacy: .public) latestAppcastVersion=\(latestVersion, privacy: .public)
            """
        )
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension AppDelegate {
    func standardUserDriverWillShowModalAlert() {
        presentUpdateUIIfNeeded()
    }

    func standardUserDriverWillFinishUpdateSession() {
        UpdateManager.shared.finishUpdateSession()
        restoreAccessoryModeIfNeeded()
    }
}
