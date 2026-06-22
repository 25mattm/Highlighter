import AppKit

/// The translucent, rounded reading bar itself. Layer-backed so it can be moved
/// and recolored cheaply while the window follows the cursor.
final class HighlightBarView: NSView {
    private let cornerRadius: CGFloat
    private var fillOpacity: CGFloat
    private var borderOpacity: CGFloat
    private var color: NSColor

    init(cornerRadius: CGFloat, color: NSColor, fillOpacity: CGFloat, borderOpacity: CGFloat) {
        self.cornerRadius = cornerRadius
        self.color = color
        self.fillOpacity = fillOpacity
        self.borderOpacity = borderOpacity
        super.init(frame: .zero)
        applyAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        return true
    }

    private func applyAppearance() {
        wantsLayer = true
        guard let layer = layer else { return }
        layer.backgroundColor = color.withAlphaComponent(fillOpacity).cgColor
        layer.cornerRadius = cornerRadius
        layer.borderColor = color.withAlphaComponent(borderOpacity).cgColor
        layer.borderWidth = 1
    }

    func updateAppearance(color: NSColor, fillOpacity: CGFloat, borderOpacity: CGFloat) {
        self.color = color
        self.fillOpacity = fillOpacity
        self.borderOpacity = borderOpacity
        applyAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        autoresizingMask = [.width, .height]
        applyAppearance()
    }
}
