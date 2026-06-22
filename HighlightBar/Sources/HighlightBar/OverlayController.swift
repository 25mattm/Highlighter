import AppKit

/// A single full-screen overlay view. Layer-backed: the layer's background is the
/// translucent tint, and an optional even-odd `CAShapeLayer` mask punches a
/// transparent slot (the spotlight cutout) out of it.
final class OverlayView: NSView {
    private let maskLayer = CAShapeLayer()
    private let cutoutCornerRadius: CGFloat
    private var fillColor: NSColor = .black
    private var fillOpacity: CGFloat = 0.5

    init(frame frameRect: NSRect, cutoutCornerRadius: CGFloat) {
        self.cutoutCornerRadius = cutoutCornerRadius
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = NSColor.black.cgColor
        // Decorative: keep VoiceOver out of the screen overlay.
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(color: NSColor, opacity: CGFloat) {
        fillColor = color
        fillOpacity = opacity
        layer?.backgroundColor = color.withAlphaComponent(opacity).cgColor
    }

    /// Sets the transparent slot in view coordinates, or `nil` for a uniform fill
    /// (tint mode, or a screen the bar is not currently on). The mask fills the
    /// area *between* the full bounds and the cutout (even-odd), so the cutout
    /// region becomes transparent and reveals the screen beneath.
    func setCutout(_ rect: NSRect?) {
        guard let layer = layer else { return }

        // Disable implicit animations so the slot tracks the cursor crisply.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let rect = rect else {
            layer.mask = nil
            return
        }

        let path = CGMutablePath()
        path.addRect(bounds)
        path.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: cutoutCornerRadius,
            cornerHeight: cutoutCornerRadius,
            transform: nil
        ))
        maskLayer.path = path
        maskLayer.frame = bounds
        layer.mask = maskLayer
    }
}

/// Owns the screen-overlay windows — one click-through window per `NSScreen`, at
/// a level just below the bar. Supports two styles:
///
/// - `.spotlight`: dims everything and follows the bar with a transparent slot.
/// - `.tint`: a uniform colored wash (no cutout) for visual-stress relief.
///
/// Overlay windows are rebuilt on display changes, reusing the same
/// click-through window factory as the bar so the always-on-top, fully
/// click-through invariant lives in one place.
final class OverlayController {
    enum Style {
        case spotlight
        case tint
    }

    private struct Overlay {
        let window: NSWindow
        let view: OverlayView
        let screenFrame: NSRect
    }

    private let windowLevel: NSWindow.Level
    private let cutoutCornerRadius: CGFloat
    private var overlays: [Overlay] = []

    private(set) var isActive = false
    private var style: Style = .spotlight
    private var color: NSColor = .systemGray
    private var opacity: CGFloat = 0.5

    init(level: NSWindow.Level, cutoutCornerRadius: CGFloat) {
        self.windowLevel = level
        self.cutoutCornerRadius = cutoutCornerRadius
    }

    /// Shows the overlay in the given style across every screen.
    func show(style: Style, color: NSColor, opacity: CGFloat) {
        self.style = style
        self.color = color
        self.opacity = opacity
        isActive = true
        rebuildForCurrentScreens()
    }

    /// Live-updates color/opacity without rebuilding windows (slider drags).
    func update(color: NSColor, opacity: CGFloat) {
        self.color = color
        self.opacity = opacity
        guard isActive else { return }
        for overlay in overlays {
            overlay.view.apply(color: color, opacity: opacity)
        }
    }

    func hide() {
        isActive = false
        teardown()
    }

    /// Rebuilds one overlay window per screen. Safe to call on display changes;
    /// a no-op while inactive.
    func rebuildForCurrentScreens() {
        teardown()
        guard isActive else { return }

        for screen in NSScreen.screens {
            let window = OverlayWindowManager.makeClickThroughWindow(level: windowLevel, contentRect: screen.frame)
            window.setFrame(screen.frame, display: false)

            let view = OverlayView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                cutoutCornerRadius: cutoutCornerRadius
            )
            view.apply(color: color, opacity: opacity)
            window.contentView = view
            window.orderFrontRegardless()

            overlays.append(Overlay(window: window, view: view, screenFrame: screen.frame))
        }

        // Tint mode never has a cutout; spotlight starts with none until the
        // first cursor update positions it.
        for overlay in overlays {
            overlay.view.setCutout(nil)
        }
    }

    /// Places the spotlight slot on the screen that contains `barFrame` (global
    /// coordinates) and clears it on all other screens. No-op unless an active
    /// spotlight is showing.
    func updateSpotlight(barFrame: NSRect) {
        guard isActive, style == .spotlight else { return }

        for overlay in overlays {
            if overlay.screenFrame.intersects(barFrame) {
                // Convert global screen coordinates to the overlay view's local,
                // non-flipped coordinates (origin at the screen's bottom-left).
                let local = NSRect(
                    x: barFrame.minX - overlay.screenFrame.minX,
                    y: barFrame.minY - overlay.screenFrame.minY,
                    width: barFrame.width,
                    height: barFrame.height
                )
                overlay.view.setCutout(local)
            } else {
                overlay.view.setCutout(nil)
            }
        }
    }

    private func teardown() {
        for overlay in overlays {
            overlay.window.orderOut(nil)
        }
        overlays.removeAll()
    }
}
