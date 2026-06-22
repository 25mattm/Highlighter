import AppKit

/// Owns the app's always-on-top, fully click-through windows and reacts to live
/// display changes. In Phase 1 it manages the single bar window; Phase 3 reuses
/// `makeClickThroughWindow` to vend one overlay window per `NSScreen`.
///
/// Every window it creates shares the same configuration that guarantees the
/// click-through invariant: `ignoresMouseEvents = true` plus a collection
/// behavior that keeps the window present on all Spaces without stealing focus,
/// so clicks, scrolling, and typing always pass straight through to the app
/// underneath.
final class OverlayWindowManager {
    /// The window that hosts the reading bar.
    let barWindow: NSWindow

    /// Invoked on the main queue whenever screen parameters change (resolution
    /// change, monitor plug/unplug). The coordinator uses this to re-clamp the
    /// bar and (Phase 3) rebuild per-screen overlays.
    var onScreenParametersChanged: (() -> Void)?

    private var screenParametersObserver: NSObjectProtocol?

    init(barLevel: NSWindow.Level) {
        barWindow = Self.makeClickThroughWindow(level: barLevel)

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onScreenParametersChanged?()
        }
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    /// Creates a borderless, transparent, always-on-top window that ignores all
    /// mouse events. Shared by the bar and the Phase 3 overlays so the
    /// click-through invariant is defined in exactly one place.
    static func makeClickThroughWindow(
        level: NSWindow.Level,
        contentRect: NSRect = NSRect(x: 0, y: 0, width: 600, height: 44)
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = level
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isMovableByWindowBackground = false
        return window
    }
}
