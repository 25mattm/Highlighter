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

    /// Frame for the bar of the given `thickness`, centered on `anchor` along its
    /// free axis and clamped so it never strands off `screen`.
    ///
    /// - Horizontal: a full-width band, vertically centered on `anchor.y`.
    /// - Vertical: a full-height column, horizontally centered on `anchor.x`.
    static func barFrame(forAnchor anchor: NSPoint, thickness: CGFloat, orientation: BarOrientation, on screen: NSScreen) -> NSRect {
        let bounds = screen.frame
        switch orientation {
        case .horizontal:
            var originY = anchor.y - thickness / 2.0
            originY = max(bounds.minY, min(originY, bounds.maxY - thickness))
            return NSRect(x: bounds.minX, y: originY, width: bounds.width, height: thickness)
        case .vertical:
            var originX = anchor.x - thickness / 2.0
            originX = max(bounds.minX, min(originX, bounds.maxX - thickness))
            return NSRect(x: originX, y: bounds.minY, width: thickness, height: bounds.height)
        }
    }
}
