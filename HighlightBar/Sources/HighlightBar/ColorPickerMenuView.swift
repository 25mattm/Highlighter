import AppKit

/// A row of color swatches embedded directly in the status-bar menu. Hovering a
/// swatch previews that color on the live bar; clicking selects it.
final class ColorPickerMenuView: NSView {
    var onHover: ((String?) -> Void)?
    var onSelect: ((String) -> Void)?
    var selectedColorName: String {
        didSet {
            needsDisplay = true
        }
    }

    private let options: [(name: String, color: NSColor)]
    private var hoverIndex: Int?
    private var trackingAreaRef: NSTrackingArea?

    private let swatchSize: CGFloat = 18
    private let spacing: CGFloat = 12
    private let horizontalInset: CGFloat = 10
    private let verticalInset: CGFloat = 6

    init(options: [(name: String, color: NSColor)], selectedColorName: String) {
        self.options = options
        self.selectedColorName = selectedColorName

        let width = (horizontalInset * 2) + CGFloat(options.count) * swatchSize + CGFloat(max(0, options.count - 1)) * spacing
        let height = swatchSize + (verticalInset * 2)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseEnteredAndExited,
            .mouseMoved,
            .inVisibleRect
        ]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHoverIndex(index(at: point))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHoverIndex(index(at: point))
    }

    override func mouseExited(with event: NSEvent) {
        updateHoverIndex(nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = index(at: point) else { return }
        selectedColorName = options[index].name
        onSelect?(selectedColorName)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for index in options.indices {
            let swatchRect = rectForSwatch(at: index)
            let option = options[index]

            let fillPath = NSBezierPath(ovalIn: swatchRect)
            option.color.setFill()
            fillPath.fill()

            let borderPath = NSBezierPath(ovalIn: swatchRect)
            NSColor.black.withAlphaComponent(0.25).setStroke()
            borderPath.lineWidth = 1
            borderPath.stroke()

            if option.name == selectedColorName {
                let selectedRect = swatchRect.insetBy(dx: -2, dy: -2)
                let selectedPath = NSBezierPath(ovalIn: selectedRect)
                NSColor.white.setStroke()
                selectedPath.lineWidth = 2
                selectedPath.stroke()
            }

            if index == hoverIndex {
                let hoverRect = swatchRect.insetBy(dx: -4, dy: -4)
                let hoverPath = NSBezierPath(ovalIn: hoverRect)
                NSColor.labelColor.withAlphaComponent(0.8).setStroke()
                hoverPath.lineWidth = 1.5
                hoverPath.stroke()
            }
        }
    }

    private func rectForSwatch(at index: Int) -> NSRect {
        let x = horizontalInset + CGFloat(index) * (swatchSize + spacing)
        return NSRect(x: x, y: verticalInset, width: swatchSize, height: swatchSize)
    }

    private func index(at point: NSPoint) -> Int? {
        for index in options.indices {
            let hitRect = rectForSwatch(at: index).insetBy(dx: -4, dy: -4)
            if hitRect.contains(point) {
                return index
            }
        }
        return nil
    }

    private func updateHoverIndex(_ index: Int?) {
        guard hoverIndex != index else { return }
        hoverIndex = index
        if let index {
            onHover?(options[index].name)
        } else {
            onHover?(nil)
        }
        needsDisplay = true
    }
}
