import AppKit
import os.log

private let logger = Logger(subsystem: "com.ruban.notchi", category: "SessionStripActions")

/// Actions invoked from a bottom-activity session strip (left click, context menu).
enum SessionStripActions {
    /// Open the session's working directory in Finder.
    @MainActor
    static func openInFinder(cwd: String) {
        let url = URL(fileURLWithPath: cwd)
        NSWorkspace.shared.open(url)
    }

    /// Open a new Ghostty window at `cwd`. Falls back to Terminal.app if Ghostty
    /// isn't installed or fails to launch with a working directory argument.
    ///
    /// Approach: Ghostty's CLI accepts `--working-directory=<path>` (see
    /// `ghostty +help`). We launch via `/usr/bin/open` with `-n -a Ghostty` and
    /// pass `--args --working-directory=<cwd>` so the new window starts in the
    /// session's directory. If Ghostty.app isn't present, fall back to
    /// `open -a Terminal <cwd>`.
    @MainActor
    static func openInGhostty(cwd: String) {
        let ghosttyPath = "/Applications/Ghostty.app"
        let ghosttyInstalled = FileManager.default.fileExists(atPath: ghosttyPath)

        if ghosttyInstalled {
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [
                "-n",
                "-a", "Ghostty",
                "--args",
                "--working-directory=\(cwd)"
            ]
            do {
                try task.run()
                return
            } catch {
                logger.error("Failed to launch Ghostty: \(error.localizedDescription, privacy: .public). Falling back to Terminal.")
            }
        } else {
            logger.info("Ghostty not installed at \(ghosttyPath, privacy: .public); falling back to Terminal.")
        }

        // Fallback: Terminal.app via NSWorkspace, which accepts a folder URL
        // as the document and opens a new shell rooted there.
        let url = URL(fileURLWithPath: cwd)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: terminalURL,
            configuration: config
        ) { _, error in
            if let error {
                logger.error("Terminal fallback failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Programmatically expand the main NotchPanel so the user can interact
    /// with the SessionListView. Selecting a specific session in the list is
    /// not currently exposed via NotchPanelManager; expansion alone is enough
    /// for the user to scroll/find the session manually.
    @MainActor
    static func revealInNotch(sessionID: String) {
        NotchPanelManager.shared.expand()
    }
}
