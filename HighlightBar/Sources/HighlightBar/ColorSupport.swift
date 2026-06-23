import AppKit

extension NSColor {
    /// "#RRGGBB" in the sRGB space. Used to persist a custom color as a spec
    /// string alongside the named presets.
    func toHexSpec() -> String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FFCC00" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Parses "#RRGGBB". The leading `#` is what distinguishes a custom spec
    /// from a preset name like "Yellow".
    static func fromHexSpec(_ spec: String) -> NSColor? {
        guard spec.hasPrefix("#") else { return nil }
        let hex = String(spec.dropFirst())
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

/// Drives the shared `NSColorPanel` for picking a custom color. Because this is
/// a menu-bar accessory app, it activates the app so the panel is interactive,
/// and routes live color changes to the supplied callback. A single instance is
/// reused for every slot (bar / overlay); each `present` re-points the panel.
final class ColorPanelController: NSObject {
    private var onChange: ((NSColor) -> Void)?

    func present(initial: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = initial
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}
