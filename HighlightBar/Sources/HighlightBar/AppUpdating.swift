import Foundation

/// Abstracts software-update checks so the App Store build — which must not
/// embed Sparkle — can substitute a no-op. The Sparkle-backed implementation is
/// `UpdaterController`, which Package.swift excludes from the App Store target.
protocol AppUpdating: AnyObject {
    func checkForUpdates()
}

/// No-op updater used when auto-update is unavailable (the App Store build).
final class NoopUpdater: AppUpdating {
    func checkForUpdates() {}
}
