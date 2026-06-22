import AppKit

/// A small one-time welcome window shown on first launch and re-showable from the
/// menu. It explains the toggle shortcut and adjustment hotkeys. Unlike the bar
/// and overlays, this is ordinary app UI and is fully available to VoiceOver.
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    private let bodyText = """
    Highlight Bar is a reading guide that follows your cursor and stays on top of \
    every window — and it is fully click-through, so it never blocks clicks, \
    scrolling, or typing.

    •  Show or hide everything anytime with  ⇧⌘H.
    •  Lock the bar in place with  ⇧⌘L,  then nudge it with  ⇧⌘↑ / ⇧⌘↓.
    •  Use the menu-bar “HB” icon to change size, color, opacity, display mode, \
    shape, tracking, and one-tap profiles.

    Everything stays on your Mac — no sign-in, no network, no data collection.
    """

    func show() {
        let window = self.window ?? buildWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Highlight Bar"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))

        let titleLabel = NSTextField(labelWithString: "Highlight Bar")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.frame = NSRect(x: 28, y: 300, width: 424, height: 30)
        container.addSubview(titleLabel)

        let body = NSTextField(wrappingLabelWithString: bodyText)
        body.font = NSFont.systemFont(ofSize: 13)
        body.frame = NSRect(x: 28, y: 72, width: 424, height: 220)
        container.addSubview(body)

        let button = NSButton(title: "Got it", target: self, action: #selector(closeTapped))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.frame = NSRect(x: 380, y: 20, width: 80, height: 32)
        button.setAccessibilityLabel("Dismiss welcome")
        container.addSubview(button)

        window.contentView = container
        window.initialFirstResponder = button
        return window
    }

    @objc private func closeTapped() {
        window?.close()
    }
}
