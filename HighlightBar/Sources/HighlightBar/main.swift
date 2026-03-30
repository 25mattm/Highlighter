import AppKit

final class HighlightBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static var retainedDelegate: HighlightBarApp?

    private enum DefaultsKey {
        static let fontReferenceSize = "fontReferenceSize"
        static let barOpacity = "barOpacity"
        static let colorName = "colorName"
    }

    private var window: NSWindow?
    private var barView: HighlightBarView?
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var fontSlider: NSSlider?
    private var opacitySlider: NSSlider?
    private var colorPickerView: ColorPickerMenuView?
    private var heightInfoItem: NSMenuItem?
    private var transparencyInfoItem: NSMenuItem?
    private var previewColorName: String?

    private var barHeight: CGFloat = 44
    private let barCornerRadius: CGFloat = 10
    private var barOpacity: CGFloat = 0.35
    private let borderOpacity: CGFloat = 0.6
    private var barColor: NSColor = .systemYellow
    private var selectedColorName = "Yellow"
    private var fontReferenceSize: CGFloat = 22
    private let defaults = UserDefaults.standard

    private let colorOptions: [(name: String, color: NSColor)] = [
        ("Yellow", .systemYellow),
        ("Green", .systemGreen),
        ("Blue", .systemBlue),
        ("Pink", .systemPink),
        ("Orange", .systemOrange),
        ("Gray", .systemGray)
    ]

    static func launch() {
        let app = NSApplication.shared
        let delegate = HighlightBarApp()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        setupStatusItem()
        createWindow()
        applyAppearance()
        updateMenuState()
        startTracking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "HB"
        item.button?.toolTip = "Highlight Bar"

        let menu = NSMenu()
        menu.delegate = self

        let heightInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        heightInfoItem.isEnabled = false
        menu.addItem(heightInfoItem)
        self.heightInfoItem = heightInfoItem

        let (fontSliderItem, fontSlider) = makeAdjustableSliderMenuItem(
            value: Double(fontReferenceSize),
            minValue: 10,
            maxValue: 100,
            sliderAction: #selector(fontReferenceChanged(_:)),
            decrementAction: #selector(decreaseFontReference(_:)),
            incrementAction: #selector(increaseFontReference(_:))
        )
        menu.addItem(fontSliderItem)
        self.fontSlider = fontSlider

        menu.addItem(.separator())

        let transparencyInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        transparencyInfoItem.isEnabled = false
        menu.addItem(transparencyInfoItem)
        self.transparencyInfoItem = transparencyInfoItem

        let (opacitySliderItem, opacitySlider) = makeAdjustableSliderMenuItem(
            value: Double(barOpacity * 100),
            minValue: 10,
            maxValue: 90,
            sliderAction: #selector(transparencyChanged(_:)),
            decrementAction: #selector(decreaseTransparency(_:)),
            incrementAction: #selector(increaseTransparency(_:))
        )
        menu.addItem(opacitySliderItem)
        self.opacitySlider = opacitySlider

        menu.addItem(.separator())

        let colorInfoItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorInfoItem.isEnabled = false
        menu.addItem(colorInfoItem)

        let colorPickerItem = NSMenuItem()
        let colorPickerView = ColorPickerMenuView(options: colorOptions, selectedColorName: selectedColorName)
        colorPickerView.onHover = { [weak self] colorName in
            self?.previewColor(named: colorName)
        }
        colorPickerView.onSelect = { [weak self] colorName in
            self?.selectColorNamed(colorName, persist: true)
        }
        colorPickerItem.view = colorPickerView
        menu.addItem(colorPickerItem)
        self.colorPickerView = colorPickerView

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Highlight Bar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu

        statusItem = item
    }

    private func createWindow() {
        let initialFrame = NSRect(x: 0, y: 0, width: 600, height: barHeight)
        let overlayWindow = NSWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.hasShadow = false
        overlayWindow.level = .screenSaver
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.isMovableByWindowBackground = false

        let barView = HighlightBarView(
            cornerRadius: barCornerRadius,
            color: barColor,
            fillOpacity: barOpacity,
            borderOpacity: currentBorderOpacity()
        )
        overlayWindow.contentView = barView

        overlayWindow.orderFrontRegardless()
        self.window = overlayWindow
        self.barView = barView
    }

    private func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateBarPosition()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateBarPosition() {
        guard let window = window else { return }
        let mouse = NSEvent.mouseLocation

        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen = targetScreen else { return }

        let frame = screen.frame
        let height = barHeight
        let width = frame.width

        var y = mouse.y - height / 2.0
        y = max(frame.minY, min(y, frame.maxY - height))

        let newFrame = NSRect(x: frame.minX, y: y, width: width, height: height)
        if window.frame != newFrame {
            window.setFrame(newFrame, display: true)
        }
    }

    private func updateMenuState() {
        heightInfoItem?.title = String(
            format: "Height: %.0f px (%.0f pt reference)",
            barHeight,
            fontReferenceSize
        )
        transparencyInfoItem?.title = String(
            format: "Transparency: %.0f%%",
            barOpacity * 100
        )
        fontSlider?.doubleValue = Double(fontReferenceSize)
        opacitySlider?.doubleValue = Double(barOpacity * 100)
        colorPickerView?.selectedColorName = selectedColorName
    }

    private func applyAppearance() {
        barView?.updateAppearance(
            color: barColor,
            fillOpacity: barOpacity,
            borderOpacity: currentBorderOpacity()
        )
    }

    private func currentBorderOpacity() -> CGFloat {
        return min(1.0, max(borderOpacity, barOpacity + 0.2))
    }

    private func colorOption(named colorName: String) -> (name: String, color: NSColor)? {
        return colorOptions.first(where: { $0.name == colorName })
    }

    private func previewColor(named colorName: String?) {
        previewColorName = colorName
        guard let colorName, let option = colorOption(named: colorName) else {
            applyAppearance()
            return
        }
        barView?.updateAppearance(
            color: option.color,
            fillOpacity: barOpacity,
            borderOpacity: currentBorderOpacity()
        )
    }

    private func clearColorPreview() {
        if previewColorName != nil {
            previewColorName = nil
            applyAppearance()
        }
    }

    private func computedBarHeight(fromFontReference fontReference: CGFloat) -> CGFloat {
        return max(18, min(200, round(fontReference * 2.0)))
    }

    private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        return Swift.max(minValue, Swift.min(value, maxValue))
    }

    private func loadSettings() {
        if let savedFontSize = defaults.object(forKey: DefaultsKey.fontReferenceSize) as? Double {
            fontReferenceSize = clamped(CGFloat(savedFontSize), min: 10, max: 100)
        }

        if let savedOpacity = defaults.object(forKey: DefaultsKey.barOpacity) as? Double {
            barOpacity = clamped(CGFloat(savedOpacity), min: 0.10, max: 0.90)
        }

        if let savedColorName = defaults.string(forKey: DefaultsKey.colorName),
           let match = colorOptions.first(where: { $0.name == savedColorName }) {
            selectedColorName = match.name
            barColor = match.color
        }

        barHeight = computedBarHeight(fromFontReference: fontReferenceSize)
    }

    private func saveSettings() {
        defaults.set(Double(fontReferenceSize), forKey: DefaultsKey.fontReferenceSize)
        defaults.set(Double(barOpacity), forKey: DefaultsKey.barOpacity)
        defaults.set(selectedColorName, forKey: DefaultsKey.colorName)
    }

    private func makeAdjustableSliderMenuItem(
        value: Double,
        minValue: Double,
        maxValue: Double,
        sliderAction: Selector,
        decrementAction: Selector,
        incrementAction: Selector
    ) -> (item: NSMenuItem, slider: NSSlider) {
        let containerWidth: CGFloat = 300
        let containerHeight: CGFloat = 30
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))

        let minusButton = NSButton(title: "-", target: self, action: decrementAction)
        minusButton.bezelStyle = .roundRect
        minusButton.frame = NSRect(x: 8, y: 3, width: 30, height: 24)
        container.addSubview(minusButton)

        let slider = NSSlider(
            value: value,
            minValue: minValue,
            maxValue: maxValue,
            target: self,
            action: sliderAction
        )
        slider.isContinuous = true
        slider.frame = NSRect(x: 44, y: 5, width: containerWidth - 88, height: 20)
        container.addSubview(slider)

        let plusButton = NSButton(title: "+", target: self, action: incrementAction)
        plusButton.bezelStyle = .roundRect
        plusButton.frame = NSRect(x: containerWidth - 38, y: 3, width: 30, height: 24)
        container.addSubview(plusButton)

        let item = NSMenuItem()
        item.view = container
        return (item, slider)
    }

    private func setFontReference(_ value: CGFloat, persist: Bool) {
        fontReferenceSize = clamped(value, min: 10, max: 100)
        barHeight = computedBarHeight(fromFontReference: fontReferenceSize)
        if persist {
            saveSettings()
        }
        updateMenuState()
        updateBarPosition()
    }

    private func setTransparencyPercent(_ percent: CGFloat, persist: Bool) {
        barOpacity = clamped(percent / 100.0, min: 0.10, max: 0.90)
        if persist {
            saveSettings()
        }
        updateMenuState()
        if let previewColorName {
            previewColor(named: previewColorName)
        } else {
            applyAppearance()
        }
    }

    private func selectColorNamed(_ colorName: String, persist: Bool) {
        guard let match = colorOption(named: colorName) else { return }

        selectedColorName = match.name
        barColor = match.color
        previewColorName = nil
        if persist {
            saveSettings()
        }
        updateMenuState()
        applyAppearance()
    }

    @objc private func fontReferenceChanged(_ sender: NSSlider) {
        setFontReference(CGFloat(sender.doubleValue), persist: true)
    }

    @objc private func decreaseFontReference(_ sender: NSButton) {
        setFontReference(fontReferenceSize - 1, persist: true)
    }

    @objc private func increaseFontReference(_ sender: NSButton) {
        setFontReference(fontReferenceSize + 1, persist: true)
    }

    @objc private func transparencyChanged(_ sender: NSSlider) {
        setTransparencyPercent(CGFloat(sender.doubleValue), persist: true)
    }

    @objc private func decreaseTransparency(_ sender: NSButton) {
        setTransparencyPercent((barOpacity * 100) - 5, persist: true)
    }

    @objc private func increaseTransparency(_ sender: NSButton) {
        setTransparencyPercent((barOpacity * 100) + 5, persist: true)
    }

    func menuDidClose(_ menu: NSMenu) {
        clearColorPreview()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

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

HighlightBarApp.launch()
