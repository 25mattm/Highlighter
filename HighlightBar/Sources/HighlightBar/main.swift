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
    private var lockMenuItem: NSMenuItem?
    private var hotKeyCenter: HotKeyCenter?
    private var nudgeUpHotKey: UInt32?
    private var nudgeDownHotKey: UInt32?
    private var isHidden = false
    private var isLocked = false
    private var lockedAnchorX: Double?
    private var lockedAnchorY: Double?
    private var previewColorName: String?

    private var overlayController: OverlayController?
    private var overlayOpacitySlider: NSSlider?
    private var overlayColorPickerView: ColorPickerMenuView?
    private var overlayInfoItem: NSMenuItem?
    private var modeMenuItems: [NSMenuItem] = []

    private var barHeight: CGFloat = 44
    private let barCornerRadius: CGFloat = 10
    private let barWindowLevel: NSWindow.Level = .screenSaver
    private var barOpacity: CGFloat = 0.35
    private let borderOpacity: CGFloat = 0.6
    private var barColor: NSColor = .systemYellow
    private var selectedColorName = "Yellow"
    private var fontReferenceSize: CGFloat = 22

    private var mode: HighlightMode = .barOnly
    private var spotlightColorName = "Gray"
    private var spotlightOpacity: CGFloat = 0.5
    private var tintColorName = "Yellow"
    private var tintOpacity: CGFloat = 0.2

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
        applyMode()
        updateMenuState()
        startTracking()
        setupHotKeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        hotKeyCenter?.unregisterAll()
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

        menu.addItem(makeModeMenuItem())

        menu.addItem(.separator())

        let lockItem = NSMenuItem(
            title: "Lock Bar Position (⇧⌘L)",
            action: #selector(toggleLock),
            keyEquivalent: ""
        )
        lockItem.target = self
        menu.addItem(lockItem)
        self.lockMenuItem = lockItem

        let visibilityItem = NSMenuItem(
            title: "Hide Highlighter (⇧⌘H)",
            action: #selector(toggleHidden),
            keyEquivalent: ""
        )
        visibilityItem.target = self
        menu.addItem(visibilityItem)
        self.visibilityMenuItem = visibilityItem

        menu.addItem(.separator())

        menu.addItem(makeShortcutsMenuItem())

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

        self.windowManager = manager
        self.barView = barView

        // Overlays sit one level below the bar so the bar stays on top of them.
        let overlayLevel = NSWindow.Level(rawValue: barWindowLevel.rawValue - 1)
        overlayController = OverlayController(level: overlayLevel, cutoutCornerRadius: barCornerRadius)

        updateBarPosition()
    }

    private func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    // One frame of tracking: reposition the bar (when its mode shows it) and, in
    // spotlight mode, move the cutout to follow it.
    private func tick() {
        guard !isHidden else { return }
        if mode.showsBar {
            updateBarPosition()
        }
        if mode == .barAndSpotlight {
            overlayController?.updateSpotlight(barFrame: windowManager?.barWindow.frame ?? .zero)
        }
    }

    private func updateBarPosition() {
        guard let window = windowManager?.barWindow else { return }
        let anchor = currentAnchor()

        guard let screen = BarGeometry.screen(containing: anchor) else { return }

        let newFrame = BarGeometry.barFrame(forMouse: anchor, height: barHeight, on: screen)
        if window.frame != newFrame {
            window.setFrame(newFrame, display: true)
        }
    }

    /// The point the bar is anchored to: the frozen lock anchor while locked,
    /// otherwise the live cursor location.
    private func currentAnchor() -> NSPoint {
        if isLocked, let x = lockedAnchorX, let y = lockedAnchorY {
            return NSPoint(x: x, y: y)
        }
        return NSEvent.mouseLocation
    }

    // Re-clamp the bar and rebuild overlays after a resolution change or monitor
    // plug/unplug. Because the cursor is always on a currently-attached screen,
    // recomputing from the mouse position lands the bar on a valid display and
    // never strands it; overlays are rebuilt to cover the new screen layout.
    private func handleScreenParametersChanged() {
        guard !isHidden else { return }
        if mode.showsBar {
            updateBarPosition()
        }
        overlayController?.rebuildForCurrentScreens()
        if mode == .barAndSpotlight {
            overlayController?.updateSpotlight(barFrame: windowManager?.barWindow.frame ?? .zero)
        }
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

        overlayOpacitySlider?.doubleValue = Double(activeOverlayOpacity * 100)
        overlayColorPickerView?.selectedColorName = activeOverlayColorName
        overlayInfoItem?.title = overlayInfoTitle()

        updateModeMenuState()
        updateLockMenuItem()
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

    // MARK: - Modes & overlays

    private var spotlightColor: NSColor {
        return colorOption(named: spotlightColorName)?.color ?? .systemGray
    }

    private var tintColor: NSColor {
        return colorOption(named: tintColorName)?.color ?? .systemYellow
    }

    // The overlay controls (in the Mode submenu) edit whichever overlay the
    // current mode uses: the tint in screen-tint mode, otherwise the spotlight.
    private var overlayTargetIsTint: Bool {
        return mode == .screenTint
    }

    private var activeOverlayOpacity: CGFloat {
        get { overlayTargetIsTint ? tintOpacity : spotlightOpacity }
        set {
            if overlayTargetIsTint { tintOpacity = newValue } else { spotlightOpacity = newValue }
        }
    }

    private var activeOverlayColorName: String {
        get { overlayTargetIsTint ? tintColorName : spotlightColorName }
        set {
            if overlayTargetIsTint { tintColorName = newValue } else { spotlightColorName = newValue }
        }
    }

    // Shows/hides the bar and overlays to match the current mode (and the master
    // hidden toggle), rebuilding overlays when an overlay mode becomes active.
    private func applyMode() {
        if !isHidden && mode.showsBar {
            windowManager?.barWindow.orderFrontRegardless()
            updateBarPosition()
        } else {
            windowManager?.barWindow.orderOut(nil)
        }

        if isHidden {
            overlayController?.hide()
        } else {
            switch mode {
            case .barAndSpotlight:
                overlayController?.show(style: .spotlight, color: spotlightColor, opacity: spotlightOpacity)
                overlayController?.updateSpotlight(barFrame: windowManager?.barWindow.frame ?? .zero)
            case .screenTint:
                overlayController?.show(style: .tint, color: tintColor, opacity: tintOpacity)
            case .off, .barOnly:
                overlayController?.hide()
            }
        }

        updateModeMenuState()
        updateVisibilityMenuItem()
    }

    // Live-updates the active overlay's color/opacity without rebuilding windows.
    private func applyOverlayAppearance() {
        guard !isHidden else { return }
        switch mode {
        case .barAndSpotlight:
            overlayController?.update(color: spotlightColor, opacity: spotlightOpacity)
        case .screenTint:
            overlayController?.update(color: tintColor, opacity: tintOpacity)
        case .off, .barOnly:
            break
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let newMode = sender.representedObject as? HighlightMode else { return }
        mode = newMode
        isHidden = false
        saveSettings()
        applyMode()
        updateMenuState()
    }

    private func setOverlayOpacityPercent(_ percent: CGFloat) {
        activeOverlayOpacity = clamped(percent / 100.0, min: 0.10, max: 0.90)
        saveSettings()
        updateMenuState()
        applyOverlayAppearance()
    }

    @objc private func overlayOpacityChanged(_ sender: NSSlider) {
        setOverlayOpacityPercent(CGFloat(sender.doubleValue))
    }

    @objc private func decreaseOverlayOpacity(_ sender: NSButton) {
        setOverlayOpacityPercent((activeOverlayOpacity * 100) - 5)
    }

    @objc private func increaseOverlayOpacity(_ sender: NSButton) {
        setOverlayOpacityPercent((activeOverlayOpacity * 100) + 5)
    }

    private func selectOverlayColor(_ colorName: String) {
        guard colorOption(named: colorName) != nil else { return }
        activeOverlayColorName = colorName
        saveSettings()
        updateMenuState()
        applyOverlayAppearance()
    }

    private func updateModeMenuState() {
        for item in modeMenuItems {
            guard let itemMode = item.representedObject as? HighlightMode else { continue }
            item.state = (itemMode == mode) ? .on : .off
        }
    }

    private func overlayInfoTitle() -> String {
        let label = overlayTargetIsTint ? "Tint" : "Spotlight"
        return String(format: "%@ opacity: %.0f%%", label, activeOverlayOpacity * 100)
    }

    private func makeModeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        modeMenuItems = []
        for highlightMode in HighlightMode.allCases {
            let modeItem = NSMenuItem(
                title: highlightMode.menuTitle,
                action: #selector(selectMode(_:)),
                keyEquivalent: ""
            )
            modeItem.target = self
            modeItem.representedObject = highlightMode
            submenu.addItem(modeItem)
            modeMenuItems.append(modeItem)
        }

        submenu.addItem(.separator())

        let overlayInfo = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        overlayInfo.isEnabled = false
        submenu.addItem(overlayInfo)
        self.overlayInfoItem = overlayInfo

        let (overlayOpacityItem, overlaySlider) = makeAdjustableSliderMenuItem(
            value: Double(activeOverlayOpacity * 100),
            minValue: 10,
            maxValue: 90,
            sliderAction: #selector(overlayOpacityChanged(_:)),
            decrementAction: #selector(decreaseOverlayOpacity(_:)),
            incrementAction: #selector(increaseOverlayOpacity(_:))
        )
        submenu.addItem(overlayOpacityItem)
        self.overlayOpacitySlider = overlaySlider

        let overlayColorLabel = NSMenuItem(title: "Overlay Color", action: nil, keyEquivalent: "")
        overlayColorLabel.isEnabled = false
        submenu.addItem(overlayColorLabel)

        let overlayColorItem = NSMenuItem()
        let overlayPicker = ColorPickerMenuView(options: colorOptions, selectedColorName: activeOverlayColorName)
        overlayPicker.onSelect = { [weak self] colorName in
            self?.selectOverlayColor(colorName)
        }
        overlayColorItem.view = overlayPicker
        submenu.addItem(overlayColorItem)
        self.overlayColorPickerView = overlayPicker

        item.submenu = submenu
        return item
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

        isLocked = settings.isLocked
        lockedAnchorX = settings.lockedAnchorX
        lockedAnchorY = settings.lockedAnchorY

        mode = settings.mode
        if colorOption(named: settings.spotlightColorName) != nil {
            spotlightColorName = settings.spotlightColorName
        }
        spotlightOpacity = clamped(CGFloat(settings.spotlightOpacity), min: 0.10, max: 0.90)
        if colorOption(named: settings.tintColorName) != nil {
            tintColorName = settings.tintColorName
        }
        tintOpacity = clamped(CGFloat(settings.tintOpacity), min: 0.10, max: 0.90)

        barHeight = computedBarHeight(fromFontReference: fontReferenceSize)
    }

    // Serializes the complete current state. Every Settings field has a backing
    // property here, so a load/save round-trip is lossless as settings grow.
    private func saveSettings() {
        var settings = Settings()
        settings.fontReferenceSize = Double(fontReferenceSize)
        settings.barOpacity = Double(barOpacity)
        settings.colorName = selectedColorName
        settings.isLocked = isLocked
        settings.lockedAnchorX = lockedAnchorX
        settings.lockedAnchorY = lockedAnchorY
        settings.mode = mode
        settings.spotlightColorName = spotlightColorName
        settings.spotlightOpacity = Double(spotlightOpacity)
        settings.tintColorName = tintColorName
        settings.tintOpacity = Double(tintOpacity)
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

    // Registers the system-wide shortcuts via Carbon's RegisterEventHotKey (no
    // Accessibility or Input Monitoring permission required, so no extra prompt).
    // Per the minimal-hotkey decision, only show/hide, lock, and nudge are
    // global; size/opacity/color stay on the menu's on-screen controls.
    private func setupHotKeys() {
        let center = HotKeyCenter()
        center.register(keyCode: kVK_ANSI_H, modifiers: [.command, .shift]) { [weak self] in
            self?.toggleHidden()
        }
        center.register(keyCode: kVK_ANSI_L, modifiers: [.command, .shift]) { [weak self] in
            self?.toggleLock()
        }
        hotKeyCenter = center
        updateNudgeHotKeys()
    }

    // The nudge shortcuts (⇧⌘↑/↓) only do anything while the bar is locked, and
    // if left always-registered they would shadow the system "select to
    // start/end of document" shortcuts in every app. So they are grabbed only
    // while locked and released as soon as the bar is unlocked.
    private func updateNudgeHotKeys() {
        guard let center = hotKeyCenter else { return }
        if isLocked {
            if nudgeUpHotKey == nil {
                nudgeUpHotKey = center.register(keyCode: kVK_UpArrow, modifiers: [.command, .shift]) { [weak self] in
                    self?.nudgeLockedBar(up: true)
                }
            }
            if nudgeDownHotKey == nil {
                nudgeDownHotKey = center.register(keyCode: kVK_DownArrow, modifiers: [.command, .shift]) { [weak self] in
                    self?.nudgeLockedBar(up: false)
                }
            }
        } else {
            if let token = nudgeUpHotKey {
                center.unregister(token)
                nudgeUpHotKey = nil
            }
            if let token = nudgeDownHotKey {
                center.unregister(token)
                nudgeDownHotKey = nil
            }
        }
    }

    @objc private func toggleLock() {
        setLocked(!isLocked, persist: true)
    }

    private func setLocked(_ locked: Bool, persist: Bool) {
        isLocked = locked
        if locked, let frame = windowManager?.barWindow.frame {
            // Freeze at exactly the bar's current center so it stays put.
            lockedAnchorX = Double(frame.midX)
            lockedAnchorY = Double(frame.midY)
        }
        if persist {
            saveSettings()
        }
        updateNudgeHotKeys()
        updateLockMenuItem()
        updateBarPosition()
    }

    // Moves the locked bar by one bar-height. The clamped result is written back
    // to the anchor so repeated nudges at a screen edge don't accumulate.
    private func nudgeLockedBar(up: Bool) {
        guard isLocked, let x = lockedAnchorX, let y = lockedAnchorY else { return }
        let anchor = NSPoint(x: x, y: y)
        guard let screen = BarGeometry.screen(containing: anchor) else { return }

        let delta = up ? barHeight : -barHeight
        let nudged = NSPoint(x: x, y: y + Double(delta))
        let frame = BarGeometry.barFrame(forMouse: nudged, height: barHeight, on: screen)
        lockedAnchorX = Double(frame.midX)
        lockedAnchorY = Double(frame.midY)
        saveSettings()
        updateBarPosition()
    }

    private func updateLockMenuItem() {
        lockMenuItem?.title = isLocked ? "Unlock Bar Position (⇧⌘L)" : "Lock Bar Position (⇧⌘L)"
    }

    // A submenu listing the global shortcuts, so they are discoverable without
    // leaving the app. Items are informational only.
    private func makeShortcutsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Keyboard Shortcuts", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let lines = [
            "⇧⌘H — Show / hide highlighter",
            "⇧⌘L — Lock / unlock position",
            "⇧⌘↑ — Nudge up (when locked)",
            "⇧⌘↓ — Nudge down (when locked)"
        ]
        for line in lines {
            let lineItem = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            lineItem.isEnabled = false
            submenu.addItem(lineItem)
        }
        item.submenu = submenu
        return item
    }

    // ⇧⌘H hides/shows the whole highlighter (bar and any overlay) so it can be
    // dismissed instantly when it would get in the way, then brought back.
    @objc private func toggleHidden() {
        isHidden.toggle()
        applyMode()
    }

    private func updateVisibilityMenuItem() {
        visibilityMenuItem?.title = isHidden ? "Show Highlighter (⇧⌘H)" : "Hide Highlighter (⇧⌘H)"
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

HighlightBarApp.launch()
