import AppKit

/// Pure geometry for placing the bar. Everything here works in AppKit *points*
/// (the global screen coordinate space), which is backing-scale independent — so
/// a given bar height renders at the same physical size on Retina and non-Retina
/// displays alike. Kept side-effect free so it can be reused by the Phase 3
/// overlays and unit-reasoned about in isolation.
enum BarGeometry {
    /// The screen currently containing `point`, falling back to the main screen.
    static func screen(containing point: NSPoint) -> NSScreen? {
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// Frame for a full-width horizontal bar of `height`, vertically centered on
    /// the cursor and clamped so it never strands off `screen`.
    static func barFrame(forMouse mouse: NSPoint, height: CGFloat, on screen: NSScreen) -> NSRect {
        let bounds = screen.frame
        var originY = mouse.y - height / 2.0
        originY = max(bounds.minY, min(originY, bounds.maxY - height))
        return NSRect(x: bounds.minX, y: originY, width: bounds.width, height: height)
    }

    /// Re-clamp an existing bar frame onto `screen` after a display change. Keeps
    /// the bar full-width on its screen and its vertical origin within bounds.
    static func clamped(frame: NSRect, height: CGFloat, on screen: NSScreen) -> NSRect {
        let bounds = screen.frame
        let originY = max(bounds.minY, min(frame.origin.y, bounds.maxY - height))
        return NSRect(x: bounds.minX, y: originY, width: bounds.width, height: height)
    }
}
