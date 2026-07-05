import AppKit
import Carbon.HIToolbox
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

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
    private var autoSuppressed = false
    private var isLocked = false
    private var lockedAnchorX: Double?
    private var lockedAnchorY: Double?
    private var previewColorName: String?

    private var overlayController: OverlayController?
    private var overlayOpacitySlider: NSSlider?
    private var overlayColorPickerView: ColorPickerMenuView?
    private var overlayInfoItem: NSMenuItem?
    private var modeMenuItems: [NSMenuItem] = []
    private var shapeMenuItems: [NSMenuItem] = []
    private var orientationMenuItems: [NSMenuItem] = []
    private var trackingMenuItems: [NSMenuItem] = []
    private var profileMenuItems: [NSMenuItem] = []
    private var deleteProfileMenuItem: NSMenuItem?
    private var profilesSubmenu: NSMenu?

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

    private var barShape: BarShape = .ruler
    private var barOrientation: BarOrientation = .horizontal
    private var trackingSource: TrackingSource = .mouse
    private var trackedPoint: NSPoint = .zero
    private var scrollMonitorGlobal: Any?
    private var scrollMonitorLocal: Any?
    private var keyMonitorGlobal: Any?
    private var keyMonitorLocal: Any?

    private let settingsStore = SettingsStore()
    private let profileStore = ProfileStore()
    private var lastAppliedProfileName: String?

#if APPSTORE
    private let updater: AppUpdating = NoopUpdater()
#else
    private let updater: AppUpdating = UpdaterController()
#endif
    private let onboardingWindow = OnboardingWindow()
    private let colorPanel = ColorPanelController()
    private var launchAtLoginMenuItem: NSMenuItem?
    private var launchAtLogin = false
    private var hasSeenOnboarding = false
    private var hasShownHotKeyConflictAlert = false

    private var perAppEnabled = false
    private var enabledBundleIDs: [String] = []
    private var perAppSubmenu: NSMenu?
    private var perAppToggleItem: NSMenuItem?
    private var appActivationObserver: NSObjectProtocol?

    // The highlighter is hidden if the user toggled it off (⇧⌘H) or per-app
    // auto-enable is suppressing it for the current frontmost app.
    private var effectivelyHidden: Bool {
        return isHidden || autoSuppressed
    }

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
        setupAppActivationObserver()
        autoSuppressed = currentlySuppressed()
        applyAppearance()
        applyMode()
        applyTrackingSource()
        updateMenuState()
        // Onboarding first: a first-run user should see the friendly welcome
        // window before any hotkey-conflict warning could block on top of it.
        showOnboardingIfFirstLaunch()
        setupHotKeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        hotKeyCenter?.unregisterAll()
        removeEventMonitors()
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A monochrome template glyph in the menu bar (adapts to light/dark and
        // the menu-bar tint). Falls back to "HB" text if the symbol is ever
        // unavailable. Not the full-color AppIcon — that renders poorly here.
        if let glyph = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "Highlight Bar") {
            glyph.isTemplate = true
            item.button?.image = glyph
        } else {
            item.button?.title = "HB"
        }
        item.button?.toolTip = "Highlight Bar"
        // VoiceOver should announce the app name, not the icon.
        item.button?.setAccessibilityLabel("Highlight Bar")

        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(makeProfilesMenuItem())

        menu.addItem(.separator())

        let heightInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        heightInfoItem.isEnabled = false
        menu.addItem(heightInfoItem)
        self.heightInfoItem = heightInfoItem

        let (fontSliderItem, fontSlider) = makeAdjustableSliderMenuItem(
            value: Double(fontReferenceSize),
            minValue: 10,
            maxValue: 100,
            accessibilityLabel: "Bar size",
            sliderAction: #selector(fontReferenceChanged(_:)),
            decrementAction: #selector(decreaseFontReference(_:)),
            incrementAction: #selector(increaseFontReference(_:))
        )
        menu.addItem(fontSliderItem)
        self.fontSlider = fontSlider

        menu.addItem(makeShapeMenuItem())
        menu.addItem(makeOrientationMenuItem())

        menu.addItem(.separator())

        let transparencyInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        transparencyInfoItem.isEnabled = false
        menu.addItem(transparencyInfoItem)
        self.transparencyInfoItem = transparencyInfoItem

        let (opacitySliderItem, opacitySlider) = makeAdjustableSliderMenuItem(
            value: Double(barOpacity * 100),
            minValue: 10,
            maxValue: 90,
            accessibilityLabel: "Bar opacity",
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
        colorPickerView.setAccessibilityLabel("Bar color")
        colorPickerView.onHover = { [weak self] colorName in
            self?.previewColor(named: colorName)
        }
        colorPickerView.onSelect = { [weak self] colorName in
            self?.selectColorNamed(colorName, persist: true)
        }
        colorPickerItem.view = colorPickerView
        menu.addItem(colorPickerItem)
        self.colorPickerView = colorPickerView

        let customColorItem = NSMenuItem(title: "Custom Color…", action: #selector(pickCustomBarColor), keyEquivalent: "")
        customColorItem.target = self
        menu.addItem(customColorItem)

        menu.addItem(.separator())

        menu.addItem(makeModeMenuItem())
        menu.addItem(makeTrackingMenuItem())
        menu.addItem(makePerAppMenuItem())

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

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        self.launchAtLoginMenuItem = launchAtLoginItem

        let welcomeItem = NSMenuItem(title: "Show Welcome…", action: #selector(showOnboarding), keyEquivalent: "")
        welcomeItem.target = self
        menu.addItem(welcomeItem)

        if Features.autoUpdate {
            let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesMenu), keyEquivalent: "")
            updatesItem.target = self
            menu.addItem(updatesItem)
        }

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

    // Starts the 60Hz tracking timer. Only called from applyMode() while the bar
    // is actually visible, so it never runs (and drains battery) while hidden,
    // suppressed, or in a mode that doesn't show the bar.
    private func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    // One frame of tracking: reposition the bar and, in spotlight mode, move the
    // cutout to follow it. applyMode() only keeps the timer alive while
    // mode.showsBar and the bar isn't effectively hidden, so both conditions
    // checked here are always true in practice; kept as a defensive guard.
    private func tick() {
        guard !effectivelyHidden else { return }
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

        let newFrame = BarGeometry.barFrame(
            forAnchor: anchor,
            thickness: currentThickness(),
            orientation: barOrientation,
            on: screen
        )
        if window.frame != newFrame {
            window.setFrame(newFrame, display: true)
        }
    }

    /// The point the bar is anchored to: the frozen lock anchor while locked, the
    /// scroll/keyboard-driven point for those tracking sources, otherwise the
    /// live cursor location.
    private func currentAnchor() -> NSPoint {
        if isLocked, let x = lockedAnchorX, let y = lockedAnchorY {
            return NSPoint(x: x, y: y)
        }
        switch trackingSource {
        case .mouse:
            return NSEvent.mouseLocation
        case .scroll, .keyboard:
            return trackedPoint
        }
    }

    // The bar's thin dimension. A ruler is a thick reading band (≈2× the font
    // reference); a line is a slim guide that still scales gently with the slider.
    private func currentThickness() -> CGFloat {
        switch barShape {
        case .ruler:
            return computedBarHeight(fromFontReference: fontReferenceSize)
        case .line:
            return max(2, min(40, round(fontReferenceSize * 0.3)))
        }
    }

    // Re-clamp the bar and rebuild overlays after a resolution change or monitor
    // plug/unplug. Because the cursor is always on a currently-attached screen,
    // recomputing from the mouse position lands the bar on a valid display and
    // never strands it; overlays are rebuilt to cover the new screen layout.
    private func handleScreenParametersChanged() {
        guard !effectivelyHidden else { return }
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
            format: "Bar size: %.0f px (%.0f pt reference)",
            currentThickness(),
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
        updateRadioState(shapeMenuItems, matching: barShape)
        updateRadioState(orientationMenuItems, matching: barOrientation)
        updateRadioState(trackingMenuItems, matching: trackingSource)
        updateProfilesMenuState()
        updateLaunchAtLoginMenuItem()
        perAppToggleItem?.state = perAppEnabled ? .on : .off
        updateLockMenuItem()
    }

    // Sets the checkmark on whichever item in a radio group holds `value`.
    private func updateRadioState<T: Equatable>(_ items: [NSMenuItem], matching value: T) {
        for item in items {
            guard let itemValue = item.representedObject as? T else { continue }
            item.state = (itemValue == value) ? .on : .off
        }
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
        return resolveColor(spotlightColorName)
    }

    private var tintColor: NSColor {
        return resolveColor(tintColorName)
    }

    // A color "spec" is either a preset name ("Yellow") or a custom "#RRGGBB".
    private func resolveColor(_ spec: String) -> NSColor {
        if let custom = NSColor.fromHexSpec(spec) { return custom }
        if let preset = colorOption(named: spec) { return preset.color }
        return .systemYellow
    }

    private func isValidColorSpec(_ spec: String) -> Bool {
        return NSColor.fromHexSpec(spec) != nil || colorOption(named: spec) != nil
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
    // Also the single place that starts/stops the 60Hz tracking timer, so it
    // only ever runs while the bar is actually visible.
    private func applyMode() {
        if !effectivelyHidden && mode.showsBar {
            windowManager?.barWindow.orderFrontRegardless()
            updateBarPosition()
            if timer == nil {
                startTracking()
            }
        } else {
            windowManager?.barWindow.orderOut(nil)
            timer?.invalidate()
            timer = nil
        }

        if effectivelyHidden {
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
        guard !effectivelyHidden else { return }
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
        setOverlayColorSpec(colorName)
    }

    @objc private func pickCustomOverlayColor() {
        colorPanel.present(initial: resolveColor(activeOverlayColorName)) { [weak self] color in
            self?.setOverlayColorSpec(color.toHexSpec())
        }
    }

    private func setOverlayColorSpec(_ spec: String) {
        activeOverlayColorName = spec
        saveSettings()
        updateMenuState()
        applyOverlayAppearance()
    }

    private func updateModeMenuState() {
        updateRadioState(modeMenuItems, matching: mode)
    }

    private func updateProfilesMenuState() {
        for item in profileMenuItems {
            guard let name = item.representedObject as? String else { continue }
            item.state = (name == lastAppliedProfileName) ? .on : .off
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
            accessibilityLabel: "Overlay opacity",
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
        overlayPicker.setAccessibilityLabel("Overlay color")
        overlayPicker.onSelect = { [weak self] colorName in
            self?.selectOverlayColor(colorName)
        }
        overlayColorItem.view = overlayPicker
        submenu.addItem(overlayColorItem)
        self.overlayColorPickerView = overlayPicker

        let overlayCustomItem = NSMenuItem(title: "Custom Overlay Color…", action: #selector(pickCustomOverlayColor), keyEquivalent: "")
        overlayCustomItem.target = self
        submenu.addItem(overlayCustomItem)

        item.submenu = submenu
        return item
    }

    // MARK: - Shape & orientation

    @objc private func selectShape(_ sender: NSMenuItem) {
        guard let newShape = sender.representedObject as? BarShape else { return }
        barShape = newShape
        saveSettings()
        updateBarPosition()
        refreshSpotlightIfNeeded()
        updateMenuState()
    }

    @objc private func selectOrientation(_ sender: NSMenuItem) {
        guard let newOrientation = sender.representedObject as? BarOrientation else { return }
        barOrientation = newOrientation
        saveSettings()
        updateBarPosition()
        refreshSpotlightIfNeeded()
        updateMenuState()
    }

    private func refreshSpotlightIfNeeded() {
        guard mode == .barAndSpotlight, !effectivelyHidden else { return }
        overlayController?.updateSpotlight(barFrame: windowManager?.barWindow.frame ?? .zero)
    }

    private func makeShapeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Shape", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        shapeMenuItems = []
        for shape in BarShape.allCases {
            let shapeItem = NSMenuItem(title: shape.menuTitle, action: #selector(selectShape(_:)), keyEquivalent: "")
            shapeItem.target = self
            shapeItem.representedObject = shape
            submenu.addItem(shapeItem)
            shapeMenuItems.append(shapeItem)
        }
        item.submenu = submenu
        return item
    }

    private func makeOrientationMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Orientation", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        orientationMenuItems = []
        for orientation in BarOrientation.allCases {
            let orientationItem = NSMenuItem(title: orientation.menuTitle, action: #selector(selectOrientation(_:)), keyEquivalent: "")
            orientationItem.target = self
            orientationItem.representedObject = orientation
            submenu.addItem(orientationItem)
            orientationMenuItems.append(orientationItem)
        }
        item.submenu = submenu
        return item
    }

    // MARK: - Tracking source

    @objc private func selectTracking(_ sender: NSMenuItem) {
        guard let newSource = sender.representedObject as? TrackingSource else { return }
        trackingSource = newSource
        saveSettings()
        applyTrackingSource()
        updateMenuState()
    }

    private func makeTrackingMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Tracking", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        trackingMenuItems = []
        for source in TrackingSource.allCases where Features.keyboardTracking || source != .keyboard {
            let sourceItem = NSMenuItem(title: source.menuTitle, action: #selector(selectTracking(_:)), keyEquivalent: "")
            sourceItem.target = self
            sourceItem.representedObject = source
            submenu.addItem(sourceItem)
            trackingMenuItems.append(sourceItem)
        }
        item.submenu = submenu
        return item
    }

    private func applyTrackingSource() {
        removeEventMonitors()
        seedTrackedPoint()
        switch trackingSource {
        case .mouse:
            break
        case .scroll:
            installScrollMonitors()
        case .keyboard:
            #if APPSTORE
            break
            #else
            installKeyboardMonitors()
            #endif
        }
    }

    // Seed the scroll/keyboard tracked point at the bar's current center (or the
    // cursor) so switching sources doesn't make the bar jump.
    private func seedTrackedPoint() {
        if let frame = windowManager?.barWindow.frame, frame.width > 0, frame.height > 0 {
            trackedPoint = NSPoint(x: frame.midX, y: frame.midY)
        } else {
            trackedPoint = NSEvent.mouseLocation
        }
    }

    private func removeEventMonitors() {
        for monitor in [scrollMonitorGlobal, scrollMonitorLocal, keyMonitorGlobal, keyMonitorLocal] {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        scrollMonitorGlobal = nil
        scrollMonitorLocal = nil
        keyMonitorGlobal = nil
        keyMonitorLocal = nil
    }

    // Scroll tracking uses NSEvent mouse-event monitors, which need no
    // Accessibility / Input Monitoring permission.
    private func installScrollMonitors() {
        scrollMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            self?.handleScroll(event)
        }
        scrollMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard trackingSource == .scroll, !effectivelyHidden, !isLocked else { return }
        switch barOrientation {
        case .horizontal: trackedPoint.y += event.scrollingDeltaY
        case .vertical:   trackedPoint.x += event.scrollingDeltaY
        }
        clampTrackedPoint()
        updateBarPosition()
        refreshSpotlightIfNeeded()
    }

#if !APPSTORE
    // Keyboard tracking needs the Input Monitoring permission, so it is opt-in
    // and primed with a clear explanation. Mouse stays the no-permission default.
    private func installKeyboardMonitors() {
        guard ensureInputMonitoringPermission() else {
            trackingSource = .mouse
            saveSettings()
            updateRadioState(trackingMenuItems, matching: trackingSource)
            return
        }
        keyMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKey(event)
        }
        keyMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKey(event)
            return event
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard trackingSource == .keyboard, !effectivelyHidden, !isLocked else { return }
        let step = currentThickness()
        switch Int(event.keyCode) {
        case kVK_UpArrow: trackedPoint.y += step
        case kVK_DownArrow: trackedPoint.y -= step
        case kVK_LeftArrow: trackedPoint.x -= step
        case kVK_RightArrow: trackedPoint.x += step
        default: return
        }
        clampTrackedPoint()
        updateBarPosition()
        refreshSpotlightIfNeeded()
    }
#endif

    private func clampTrackedPoint() {
        guard let screen = BarGeometry.screen(containing: trackedPoint) else { return }
        let bounds = screen.frame
        trackedPoint.x = max(bounds.minX, min(trackedPoint.x, bounds.maxX))
        trackedPoint.y = max(bounds.minY, min(trackedPoint.y, bounds.maxY))
    }

#if !APPSTORE
    // Triggers the Input Monitoring prompt and reports whether access is granted.
    private func ensureInputMonitoringPermission() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        let granted = CGRequestListenEventAccess()
        if !granted {
            presentInputMonitoringHelp()
        }
        return granted
    }

    private func presentInputMonitoringHelp() {
        let alert = NSAlert()
        alert.messageText = "Keyboard tracking needs Input Monitoring"
        alert.informativeText = "To drive the bar with the arrow keys, grant Highlight Bar access under System Settings → Privacy & Security → Input Monitoring, then choose Keyboard tracking again. Until then, tracking stays on Mouse."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
#endif

    // MARK: - Profiles

    @objc private func applyProfileMenuItem(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let profile = profileStore.allProfiles().first(where: { $0.name == name }) else { return }
        applyProfile(profile)
    }

    private func applyProfile(_ profile: Profile) {
        // Profiles carry only appearance/behavior fields (see
        // currentSettingsSnapshot); the snapshot's other fields are defaults.
        // Keep the live app-level state — lock, login item, onboarding,
        // per-app list — so applying a profile can't wipe it.
        var merged = profile.settings
        merged.isLocked = isLocked
        merged.lockedAnchorX = lockedAnchorX
        merged.lockedAnchorY = lockedAnchorY
        merged.launchAtLogin = launchAtLogin
        merged.hasSeenOnboarding = hasSeenOnboarding
        merged.perAppEnabled = perAppEnabled
        merged.enabledBundleIDs = enabledBundleIDs
        merged.hasShownHotKeyConflictAlert = hasShownHotKeyConflictAlert
        adopt(merged)
        lastAppliedProfileName = profile.name
        profileStore.lastAppliedName = profile.name
        saveSettings()

        // Refresh every subsystem to match the freshly-adopted settings.
        applyAppearance()
        applyTrackingSource()
        applyMode()
        updateNudgeHotKeys()
        updateMenuState()
    }

    @objc private func saveCurrentAsProfile() {
        guard let name = promptForProfileName() else { return }
        let snapshot = currentSettingsSnapshot()
        var customs = profileStore.loadCustom()
        if let index = customs.firstIndex(where: { $0.name == name }) {
            customs[index] = Profile(name: name, settings: snapshot, isBuiltIn: false)
        } else {
            customs.append(Profile(name: name, settings: snapshot, isBuiltIn: false))
        }
        profileStore.saveCustom(customs)
        lastAppliedProfileName = name
        profileStore.lastAppliedName = name
        rebuildProfilesSubmenu()
        updateMenuState()
    }

    @objc private func deleteCustomProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        var customs = profileStore.loadCustom()
        customs.removeAll { $0.name == name }
        profileStore.saveCustom(customs)
        if lastAppliedProfileName == name {
            lastAppliedProfileName = nil
            profileStore.lastAppliedName = nil
        }
        rebuildProfilesSubmenu()
        updateMenuState()
    }

    private func promptForProfileName() -> String? {
        let alert = NSAlert()
        alert.messageText = "Save Current Settings as Profile"
        alert.informativeText = "Enter a name for this profile."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "My profile"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func makeProfilesMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        item.submenu = submenu
        profilesSubmenu = submenu
        rebuildProfilesSubmenu()
        return item
    }

    // Repopulates the Profiles submenu so newly-saved/deleted customs appear.
    private func rebuildProfilesSubmenu() {
        guard let submenu = profilesSubmenu else { return }
        submenu.removeAllItems()
        profileMenuItems = []

        for profile in profileStore.allProfiles() {
            let profileItem = NSMenuItem(title: profile.name, action: #selector(applyProfileMenuItem(_:)), keyEquivalent: "")
            profileItem.target = self
            profileItem.representedObject = profile.name
            submenu.addItem(profileItem)
            profileMenuItems.append(profileItem)
        }

        submenu.addItem(.separator())

        let saveItem = NSMenuItem(title: "Save Current as…", action: #selector(saveCurrentAsProfile), keyEquivalent: "")
        saveItem.target = self
        submenu.addItem(saveItem)

        let customs = profileStore.loadCustom()
        let deleteItem = NSMenuItem(title: "Delete Saved Profile", action: nil, keyEquivalent: "")
        if customs.isEmpty {
            deleteItem.isEnabled = false
        } else {
            let deleteSubmenu = NSMenu()
            for profile in customs {
                let deleteEntry = NSMenuItem(title: profile.name, action: #selector(deleteCustomProfile(_:)), keyEquivalent: "")
                deleteEntry.target = self
                deleteEntry.representedObject = profile.name
                deleteSubmenu.addItem(deleteEntry)
            }
            deleteItem.submenu = deleteSubmenu
        }
        submenu.addItem(deleteItem)
        deleteProfileMenuItem = deleteItem

        updateProfilesMenuState()
    }

    // MARK: - Launch at login, onboarding, updates

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginEnabled())
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Highlight Bar: launch-at-login update failed: \(error.localizedDescription)")
        }
        launchAtLogin = isLaunchAtLoginEnabled()
        saveSettings()
        updateLaunchAtLoginMenuItem()
    }

    private func updateLaunchAtLoginMenuItem() {
        launchAtLoginMenuItem?.state = isLaunchAtLoginEnabled() ? .on : .off
    }

    @objc private func showOnboarding() {
        onboardingWindow.show()
    }

    private func showOnboardingIfFirstLaunch() {
        guard !hasSeenOnboarding else { return }
        hasSeenOnboarding = true
        saveSettings()
        onboardingWindow.show()
    }

    @objc private func checkForUpdatesMenu() {
        updater.checkForUpdates()
    }

    // MARK: - Per-app auto-enable

    private func setupAppActivationObserver() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAutoSuppression()
        }
    }

    // Whether per-app rules say to hide right now, based on the frontmost app.
    private func currentlySuppressed() -> Bool {
        guard perAppEnabled, !enabledBundleIDs.isEmpty else { return false }
        guard let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return true }
        // Our own activation (e.g. opening the color panel) shouldn't flip state.
        if frontID == Bundle.main.bundleIdentifier { return autoSuppressed }
        return !enabledBundleIDs.contains(frontID)
    }

    @objc private func updateAutoSuppression() {
        let newValue = currentlySuppressed()
        guard newValue != autoSuppressed else { return }
        autoSuppressed = newValue
        applyMode()
    }

    @objc private func togglePerApp() {
        perAppEnabled.toggle()
        saveSettings()
        rebuildPerAppSubmenu()
        updateAutoSuppression()
    }

    @objc private func addEnabledApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        guard !enabledBundleIDs.contains(bundleID) else { return }
        enabledBundleIDs.append(bundleID)
        saveSettings()
        rebuildPerAppSubmenu()
        updateAutoSuppression()
    }

    @objc private func removeEnabledApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        enabledBundleIDs.removeAll { $0 == bundleID }
        saveSettings()
        rebuildPerAppSubmenu()
        updateAutoSuppression()
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }

    private func makePerAppMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Auto-Enable in Apps", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        item.submenu = submenu
        perAppSubmenu = submenu
        rebuildPerAppSubmenu()
        return item
    }

    // Repopulates the per-app submenu: a toggle, the chosen apps (each with a
    // Remove subitem), and an Add entry.
    private func rebuildPerAppSubmenu() {
        guard let submenu = perAppSubmenu else { return }
        submenu.removeAllItems()

        let toggle = NSMenuItem(title: "Only in Selected Apps", action: #selector(togglePerApp), keyEquivalent: "")
        toggle.target = self
        toggle.state = perAppEnabled ? .on : .off
        submenu.addItem(toggle)
        perAppToggleItem = toggle

        submenu.addItem(.separator())

        if enabledBundleIDs.isEmpty {
            let empty = NSMenuItem(title: "No apps added", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for bundleID in enabledBundleIDs {
                let appItem = NSMenuItem(title: appName(for: bundleID), action: nil, keyEquivalent: "")
                let appSubmenu = NSMenu()
                let remove = NSMenuItem(title: "Remove", action: #selector(removeEnabledApp(_:)), keyEquivalent: "")
                remove.target = self
                remove.representedObject = bundleID
                appSubmenu.addItem(remove)
                appItem.submenu = appSubmenu
                submenu.addItem(appItem)
            }
        }

        submenu.addItem(.separator())

        let add = NSMenuItem(title: "Add an App…", action: #selector(addEnabledApp), keyEquivalent: "")
        add.target = self
        submenu.addItem(add)
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
        adopt(settingsStore.load())
        lastAppliedProfileName = profileStore.lastAppliedName
    }

    // Loads a Settings value into the live properties (with clamping/validation).
    // Used both at launch and when applying a profile.
    private func adopt(_ settings: Settings) {
        fontReferenceSize = clamped(CGFloat(settings.fontReferenceSize), min: 10, max: 100)
        barOpacity = clamped(CGFloat(settings.barOpacity), min: 0.10, max: 0.90)

        if isValidColorSpec(settings.colorName) {
            selectedColorName = settings.colorName
            barColor = resolveColor(settings.colorName)
        }

        isLocked = settings.isLocked
        lockedAnchorX = settings.lockedAnchorX
        lockedAnchorY = settings.lockedAnchorY

        mode = settings.mode
        if isValidColorSpec(settings.spotlightColorName) {
            spotlightColorName = settings.spotlightColorName
        }
        spotlightOpacity = clamped(CGFloat(settings.spotlightOpacity), min: 0.10, max: 0.90)
        if isValidColorSpec(settings.tintColorName) {
            tintColorName = settings.tintColorName
        }
        tintOpacity = clamped(CGFloat(settings.tintOpacity), min: 0.10, max: 0.90)

        barShape = settings.barShape
        barOrientation = settings.barOrientation
        trackingSource = settings.trackingSource
        // Keyboard tracking is unavailable in the sandboxed App Store build;
        // coerce any persisted/migrated value back to mouse so it isn't applied.
        if !Features.keyboardTracking, trackingSource == .keyboard {
            trackingSource = .mouse
        }

        launchAtLogin = settings.launchAtLogin
        hasSeenOnboarding = settings.hasSeenOnboarding
        perAppEnabled = settings.perAppEnabled
        enabledBundleIDs = settings.enabledBundleIDs
        hasShownHotKeyConflictAlert = settings.hasShownHotKeyConflictAlert
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
        settings.barShape = barShape
        settings.barOrientation = barOrientation
        settings.trackingSource = trackingSource
        settings.launchAtLogin = launchAtLogin
        settings.hasSeenOnboarding = hasSeenOnboarding
        settings.perAppEnabled = perAppEnabled
        settings.enabledBundleIDs = enabledBundleIDs
        settings.hasShownHotKeyConflictAlert = hasShownHotKeyConflictAlert
        settingsStore.save(settings)
    }

    // A snapshot of the current configuration for saving as a custom profile.
    // Lock state/position are excluded so a profile stays portable across setups.
    private func currentSettingsSnapshot() -> Settings {
        var settings = Settings()
        settings.fontReferenceSize = Double(fontReferenceSize)
        settings.barOpacity = Double(barOpacity)
        settings.colorName = selectedColorName
        settings.mode = mode
        settings.spotlightColorName = spotlightColorName
        settings.spotlightOpacity = Double(spotlightOpacity)
        settings.tintColorName = tintColorName
        settings.tintOpacity = Double(tintOpacity)
        settings.barShape = barShape
        settings.barOrientation = barOrientation
        settings.trackingSource = trackingSource
        return settings
    }

    private func makeAdjustableSliderMenuItem(
        value: Double,
        minValue: Double,
        maxValue: Double,
        accessibilityLabel: String,
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
        minusButton.setAccessibilityLabel("Decrease \(accessibilityLabel)")
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
        slider.setAccessibilityLabel(accessibilityLabel)
        container.addSubview(slider)

        let plusButton = NSButton(title: "+", target: self, action: incrementAction)
        plusButton.bezelStyle = .roundRect
        plusButton.frame = NSRect(x: containerWidth - 38, y: 3, width: 30, height: 24)
        plusButton.setAccessibilityLabel("Increase \(accessibilityLabel)")
        container.addSubview(plusButton)

        let item = NSMenuItem()
        item.view = container
        return (item, slider)
    }

    private func setFontReference(_ value: CGFloat, persist: Bool) {
        fontReferenceSize = clamped(value, min: 10, max: 100)
        if persist {
            saveSettings()
        }
        updateMenuState()
        updateBarPosition()
        refreshSpotlightIfNeeded()
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
        applyBarColor(spec: match.name, color: match.color)
    }

    @objc private func pickCustomBarColor() {
        colorPanel.present(initial: barColor) { [weak self] color in
            self?.applyBarColor(spec: color.toHexSpec(), color: color)
        }
    }

    private func applyBarColor(spec: String, color: NSColor) {
        selectedColorName = spec
        barColor = color
        previewColorName = nil
        saveSettings()
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
        var failedShortcuts: [String] = []

        if center.register(keyCode: kVK_ANSI_H, modifiers: [.command, .shift], handler: { [weak self] in
            self?.toggleHidden()
        }) == nil {
            failedShortcuts.append("⇧⌘H (Hide Highlighter)")
        }
        if center.register(keyCode: kVK_ANSI_L, modifiers: [.command, .shift], handler: { [weak self] in
            self?.toggleLock()
        }) == nil {
            failedShortcuts.append("⇧⌘L (Lock Bar Position)")
        }
        hotKeyCenter = center
        updateNudgeHotKeys()

        // Only the core shortcuts get a heads-up: both remain fully usable from
        // the menu bar item, so this is a one-time convenience notice, not a
        // broken-feature alert. The nudge shortcuts (re-registered on every
        // lock/unlock) are deliberately left silent - flagging those too would
        // fire the same alert repeatedly and add noise for a minor feature.
        // Gated on hasShownHotKeyConflictAlert so a permanently-conflicting
        // shortcut (another app that always owns it) shows this once ever,
        // not as a modal on every single launch.
        if !failedShortcuts.isEmpty && !hasShownHotKeyConflictAlert {
            hasShownHotKeyConflictAlert = true
            saveSettings()
            presentHotKeyConflictAlert(for: failedShortcuts)
        }
    }

    private func presentHotKeyConflictAlert(for failedShortcuts: [String]) {
        let alert = NSAlert()
        alert.messageText = "Some Highlight Bar shortcuts are unavailable"
        alert.informativeText = "\(failedShortcuts.joined(separator: " and ")) couldn't be registered, probably because another running app already uses that combination. You can still trigger these from the Highlight Bar menu bar icon."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

        let thickness = currentThickness()
        let delta = up ? thickness : -thickness
        // Nudge along the bar's free axis: vertically for a horizontal band,
        // horizontally for a vertical column.
        let nudged: NSPoint
        switch barOrientation {
        case .horizontal: nudged = NSPoint(x: x, y: y + Double(delta))
        case .vertical:   nudged = NSPoint(x: x + Double(delta), y: y)
        }
        let frame = BarGeometry.barFrame(forAnchor: nudged, thickness: thickness, orientation: barOrientation, on: screen)
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
