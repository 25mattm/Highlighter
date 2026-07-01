// Compile-time feature switches that differ between the direct-download build
// and the sandboxed Mac App Store build. The APPSTORE flag is set in
// Package.swift when building with HB_APPSTORE=1.
//
// The sandbox spike (June 2026) confirmed everything else — overlays, custom
// colors, per-app auto-enable, scroll tracking, global hotkeys, login item —
// works under the App Sandbox; only these two need to differ.
enum Features {
#if APPSTORE
    /// Sparkle auto-update is removed in the App Store build — the store handles
    /// updates, and third-party updaters are disallowed.
    static let autoUpdate = false
    /// Keyboard tracking needs Input Monitoring, which the App Sandbox cannot
    /// grant, so it is hidden in the App Store build (mouse + scroll remain).
    static let keyboardTracking = false
#else
    static let autoUpdate = true
    static let keyboardTracking = true
#endif
}
