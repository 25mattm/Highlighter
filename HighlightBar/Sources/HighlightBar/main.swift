import AppKit
import Carbon.HIToolbox

final class HighlightBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static var retainedDelegate: HighlightBarApp?

    private var windowManager: OverlayWindowManager?
    private var barView: HighlightBarView?
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var fontSlider: NSSlider?
    private var opacitySlider: NSSlider?
    private var colorPickerView: ColorPickerMenuView?
    private var heightInfoItem: NSMenuItem?
    private var transparencyInfoItem: NSMenuItem?
    private var visibilityMenuItem: NSMenuItem?
    private var hotKeyRef: EventHotKeyRef?
    private var isBarHidden = false
    private var previewColorName: String?

    private var barHeight: CGFloat = 44
    private let barCornerRadius: CGFloat = 10
    private let barWindowLevel: NSWindow.Level = .screenSaver
    private var barOpacity: CGFloat = 0.35
    private let borderOpacity: CGFloat = 0.6
    private var barColor: NSColor = .systemYellow
    private var selectedColorName = "Yellow"
    private var fontReferenceSize: CGFloat = 22
    private let settingsStore = SettingsStore()

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
        registerGlobalHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
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

        let visibilityItem = NSMenuItem(
            title: "Hide Bar (⇧⌘H)",
            action: #selector(toggleBarVisibility),
            keyEquivalent: ""
        )
        visibilityItem.target = self
        menu.addItem(visibilityItem)
        self.visibilityMenuItem = visibilityItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Highlight Bar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu

        statusItem = item
    }

    private func createWindow() {
        let manager = OverlayWindowManager(barLevel: barWindowLevel)
        manager.onScreenParametersChanged = { [weak self] in
            self?.handleScreenParametersChanged()
        }

        let barView = HighlightBarView(
            cornerRadius: barCornerRadius,
            color: barColor,
            fillOpacity: barOpacity,
            borderOpacity: currentBorderOpacity()
        )
        manager.barWindow.contentView = barView
        manager.barWindow.orderFrontRegardless()

        self.windowManager = manager
        self.barView = barView

        updateBarPosition()
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
        guard let window = windowManager?.barWindow else { return }
        let mouse = NSEvent.mouseLocation

        guard let screen = BarGeometry.screen(containing: mouse) else { return }

        let newFrame = BarGeometry.barFrame(forMouse: mouse, height: barHeight, on: screen)
        if window.frame != newFrame {
            window.setFrame(newFrame, display: true)
        }
    }

    // Re-clamp the bar after a resolution change or monitor plug/unplug. Because
    // the cursor is always on a currently-attached screen, recomputing from the
    // mouse position lands the bar on a valid display and never strands it.
    private func handleScreenParametersChanged() {
        guard !isBarHidden else { return }
        updateBarPosition()
    }

    private func updateMenuState() {
        heightInfoItem?.title = String(
            format: "Height: %.0f px (%.0f pt reference)",
            barHeight,
            fontReferenceSize
        )
        transparencyInfoItem?.title = String(
            format: "Opacity: %.0f%% (%.0f%% transparent)",
            barOpacity * 100,
            100 - barOpacity * 100
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
        let settings = settingsStore.load()

        fontReferenceSize = clamped(CGFloat(settings.fontReferenceSize), min: 10, max: 100)
        barOpacity = clamped(CGFloat(settings.barOpacity), min: 0.10, max: 0.90)

        if let match = colorOptions.first(where: { $0.name == settings.colorName }) {
            selectedColorName = match.name
            barColor = match.color
        }

        barHeight = computedBarHeight(fromFontReference: fontReferenceSize)
    }

    private func saveSettings() {
        let settings = Settings(
            fontReferenceSize: Double(fontReferenceSize),
            barOpacity: Double(barOpacity),
            colorName: selectedColorName
        )
        settingsStore.save(settings)
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

    // Registers a system-wide ⇧⌘H shortcut to show/hide the bar. Carbon's
    // RegisterEventHotKey is used because it does not require Accessibility or
    // Input Monitoring permission, so the shortcut works without an extra prompt.
    private func registerGlobalHotKey() {
        let signature: OSType = 0x4842_4B31 // "HBK1"
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let app = Unmanaged<HighlightBarApp>.fromOpaque(userData).takeUnretainedValue()
                app.toggleBarVisibility()
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    @objc private func toggleBarVisibility() {
        isBarHidden.toggle()
        if isBarHidden {
            windowManager?.barWindow.orderOut(nil)
        } else {
            windowManager?.barWindow.orderFrontRegardless()
            updateBarPosition()
        }
        updateVisibilityMenuItem()
    }

    private func updateVisibilityMenuItem() {
        visibilityMenuItem?.title = isBarHidden ? "Show Bar (⇧⌘H)" : "Hide Bar (⇧⌘H)"
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

HighlightBarApp.launch()
