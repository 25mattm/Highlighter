import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater.
///
/// The updater is created lazily, only when the user first chooses "Check for
/// Updates…", and automatic background checks are disabled — so the app makes no
/// network request unless the user explicitly opts in, preserving the
/// local-only invariant. The appcast feed URL and the EdDSA public key are read
/// from Info.plist (`SUFeedURL`, `SUPublicEDKey`), which the build script writes.
final class UpdaterController {
    private var controller: SPUStandardUpdaterController?

    /// True only in a packaged .app whose Info.plist carries the update config.
    /// In a bare `swift run` build these keys are absent, so we avoid starting
    /// Sparkle (which expects them) and explain instead.
    private var isUpdateConfigured: Bool {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    }

    @objc func checkForUpdates() {
        guard isUpdateConfigured else {
            presentUnavailableAlert()
            return
        }
        makeOrGetController().checkForUpdates(nil)
    }

    private func makeOrGetController() -> SPUStandardUpdaterController {
        if let controller {
            return controller
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // No automatic/background checks — updates happen only on explicit request.
        controller.updater.automaticallyChecksForUpdates = false
        self.controller = controller
        return controller
    }

    private func presentUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = "Updates are available in the released app"
        alert.informativeText = "This build was run from source. Download Highlight Bar from its Releases page to receive automatic update checks."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
