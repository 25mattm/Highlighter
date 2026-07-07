using System.Drawing;
using System.Windows.Forms;

namespace HighlightBar.Windows;

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly Dictionary<string, Color> _colors = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Yellow"] = Color.Gold,
        ["Green"] = Color.MediumSpringGreen,
        ["Blue"] = Color.DeepSkyBlue,
        ["Pink"] = Color.HotPink,
        ["Orange"] = Color.Orange,
        ["Gray"] = Color.Silver
    };

    private readonly Dictionary<string, ToolStripMenuItem> _colorMenuItems = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<BarShape, ToolStripMenuItem> _barShapeMenuItems = new();
    private readonly Dictionary<BarOrientation, ToolStripMenuItem> _barOrientationMenuItems = new();
    private readonly Dictionary<HighlightMode, ToolStripMenuItem> _highlightModeMenuItems = new();
    private readonly Dictionary<string, ToolStripMenuItem> _profileMenuItems = new(StringComparer.OrdinalIgnoreCase);
    private readonly OverlayForm _overlay;
    private readonly NotifyIcon _notifyIcon;
    private readonly System.Windows.Forms.Timer _followTimer;
    private readonly AppSettings _settings;
    private readonly ProfileStore _profileStore;
    private readonly ToolStripMenuItem _fontLabelItem = new() { Enabled = false };
    private readonly ToolStripMenuItem _opacityLabelItem = new() { Enabled = false };
    private readonly ToolStripMenuItem _visibilityItem = new("Hide Bar (Ctrl+Shift+H)");
    private readonly ToolStripMenuItem _lockItem = new("Lock Position");
    private readonly ToolStripMenuItem _startupItem = new("Launch at startup");

    private string? _previewColorName;
    private bool _barHidden;
    private Point _lockAnchorPoint;
    private int _scrollAccumulation = 0;
    private System.Windows.Forms.Timer? _scrollSettleTimer;
    private readonly List<ScreenTintOverlayForm> _screenTintOverlays = new();
    private SpotlightOverlayForm? _spotlightOverlay;

    public TrayApplicationContext()
    {
        _settings = SettingsStore.Load();
        _profileStore = new ProfileStore();
        NormalizeSettings();

        _overlay = new OverlayForm();
        _overlay.ToggleRequested += (_, _) => ToggleVisibility();
        _overlay.LockToggleRequested += (_, _) => ToggleLock();
        _overlay.NudgeUpRequested += (_, _) => Nudge(delta: -10);
        _overlay.NudgeDownRequested += (_, _) => Nudge(delta: 10);
        _overlay.ScrollRequested += (_, e) => OnScroll(e);
        _overlay.KeyboardTrackingRequested += (_, e) => OnKeyboard(e);
        _overlay.DisplayChanged += (_, _) => OnDisplayChanged();
        _overlay.HotKeyConflictDetected += (_, e) => OnHotKeyConflict(e);
        ApplySettingsToOverlay();
        _overlay.Show();

        var menu = BuildMenu();
        _notifyIcon = new NotifyIcon
        {
            Text = "Highlight Bar",
            Icon = SystemIcons.Application,
            ContextMenuStrip = menu,
            Visible = true
        };

        InsertValueLabels(menu);
        UpdateMenuLabels();
        UpdateColorChecks();
        UpdateLockState();
        UpdateStartupState();

        _followTimer = new System.Windows.Forms.Timer { Interval = 16 };
        _followTimer.Tick += (_, _) =>
        {
            if (!_barHidden && _settings.TrackingSource == TrackingSource.Mouse)
            {
                _overlay.FollowCursor(Cursor.Position);
            }
            // Update overlay positions if in spotlight or tint mode
            UpdateSpotlightPosition();
        };
        _followTimer.Start();

        // Show onboarding on first launch
        if (!_settings.HasSeenOnboarding)
        {
            ShowOnboarding();
        }
    }

    private void ShowOnboarding()
    {
        using (var form = new OnboardingForm())
        {
            form.ShowDialog();
        }

        _settings.HasSeenOnboarding = true;
        SaveSettings();
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip
        {
            ShowImageMargin = false
        };

        menu.Closing += (_, _) => ClearPreviewColor();

        var decreaseFontItem = new ToolStripMenuItem("Smaller Font Reference (-1)", null, (_, _) => ChangeFontReference(-1));
        var increaseFontItem = new ToolStripMenuItem("Larger Font Reference (+1)", null, (_, _) => ChangeFontReference(1));

        var decreaseOpacityItem = new ToolStripMenuItem("More Transparent (-5%)", null, (_, _) => ChangeOpacity(-5));
        var increaseOpacityItem = new ToolStripMenuItem("More Solid (+5%)", null, (_, _) => ChangeOpacity(5));

        var colorHeader = new ToolStripMenuItem("Color");
        foreach (var colorName in _colors.Keys)
        {
            var item = new ToolStripMenuItem(colorName);
            item.Click += (_, _) => SelectColor(colorName, persist: true);
            item.MouseEnter += (_, _) => PreviewColor(colorName);
            item.MouseLeave += (_, _) => ClearPreviewColor();
            _colorMenuItems[colorName] = item;
            colorHeader.DropDownItems.Add(item);
        }

        var barShapeHeader = new ToolStripMenuItem("Bar Shape");
        foreach (var shape in new[] { BarShape.Ruler, BarShape.Line })
        {
            var shapeName = shape == BarShape.Ruler ? "Ruler (band)" : "Line (thin)";
            var item = new ToolStripMenuItem(shapeName);
            item.Click += (_, _) => SelectBarShape(shape, persist: true);
            _barShapeMenuItems[shape] = item;
            barShapeHeader.DropDownItems.Add(item);
        }

        var barOrientationHeader = new ToolStripMenuItem("Orientation");
        foreach (var orientation in new[] { BarOrientation.Horizontal, BarOrientation.Vertical })
        {
            var orientationName = orientation == BarOrientation.Horizontal ? "Horizontal" : "Vertical (column)";
            var item = new ToolStripMenuItem(orientationName);
            item.Click += (_, _) => SelectBarOrientation(orientation, persist: true);
            _barOrientationMenuItems[orientation] = item;
            barOrientationHeader.DropDownItems.Add(item);
        }

        var modeHeader = new ToolStripMenuItem("Display Mode");
        foreach (var mode in new[] { HighlightMode.BarOnly, HighlightMode.BarAndSpotlight, HighlightMode.ScreenTint })
        {
            var modeName = mode == HighlightMode.BarOnly ? "Bar only" :
                          mode == HighlightMode.BarAndSpotlight ? "Bar + spotlight" :
                          "Screen tint";
            var item = new ToolStripMenuItem(modeName);
            item.Click += (_, _) => SelectHighlightMode(mode, persist: true);
            _highlightModeMenuItems[mode] = item;
            modeHeader.DropDownItems.Add(item);
        }

        var profileHeader = new ToolStripMenuItem("Profiles");
        foreach (var profile in _profileStore.GetAllProfiles())
        {
            var item = new ToolStripMenuItem(profile.Name);
            item.Click += (_, _) => ApplyProfile(profile, persist: true);
            _profileMenuItems[profile.Name] = item;
            profileHeader.DropDownItems.Add(item);
        }

        _lockItem.Click += (_, _) => ToggleLock();
        _visibilityItem.Click += (_, _) => ToggleVisibility();
        _startupItem.Click += (_, _) => ToggleStartup();

        var quitItem = new ToolStripMenuItem("Quit Highlight Bar", null, (_, _) => ExitApp());

        menu.Items.Add(decreaseFontItem);
        menu.Items.Add(increaseFontItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(decreaseOpacityItem);
        menu.Items.Add(increaseOpacityItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(colorHeader);
        menu.Items.Add(barShapeHeader);
        menu.Items.Add(barOrientationHeader);
        menu.Items.Add(modeHeader);
        menu.Items.Add(profileHeader);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_lockItem);
        menu.Items.Add(_startupItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_visibilityItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(quitItem);

        return menu;
    }

    private void InsertValueLabels(ContextMenuStrip menu)
    {
        menu.Items.Insert(0, _fontLabelItem);
        menu.Items.Insert(1, new ToolStripSeparator());
        menu.Items.Insert(5, _opacityLabelItem);
        menu.Items.Insert(6, new ToolStripSeparator());
    }

    private void UpdateMenuLabels()
    {
        _fontLabelItem.Text = $"Height: {_settings.FontReferenceSize * 2}px ({_settings.FontReferenceSize}pt reference)";
        _opacityLabelItem.Text = $"Opacity: {_settings.BarOpacityPercent}% ({100 - _settings.BarOpacityPercent}% transparent)";
    }

    private void UpdateColorChecks()
    {
        foreach (var (name, item) in _colorMenuItems)
        {
            item.Checked = name.Equals(_settings.ColorName, StringComparison.OrdinalIgnoreCase);
        }
    }

    private void UpdateShapeChecks()
    {
        foreach (var (shape, item) in _barShapeMenuItems)
        {
            item.Checked = shape == _settings.BarShape;
        }
    }

    private void UpdateOrientationChecks()
    {
        foreach (var (orientation, item) in _barOrientationMenuItems)
        {
            item.Checked = orientation == _settings.BarOrientation;
        }
    }

    private void UpdateModeChecks()
    {
        foreach (var (mode, item) in _highlightModeMenuItems)
        {
            item.Checked = mode == _settings.Mode;
        }
    }

    private void ChangeFontReference(int delta)
    {
        _settings.FontReferenceSize = Math.Clamp(_settings.FontReferenceSize + delta, 10, 100);
        ApplySettingsToOverlay();
        SaveSettings();
    }

    private void ChangeOpacity(int deltaPercent)
    {
        _settings.BarOpacityPercent = Math.Clamp(_settings.BarOpacityPercent + deltaPercent, 10, 90);
        ApplySettingsToOverlay();
        SaveSettings();
    }

    private void PreviewColor(string colorName)
    {
        if (!_colors.TryGetValue(colorName, out var color))
        {
            return;
        }

        _previewColorName = colorName;
        _overlay.SetAppearance(color, _settings.BarOpacityPercent);
    }

    private void ClearPreviewColor()
    {
        if (_previewColorName is null)
        {
            return;
        }

        _previewColorName = null;
        ApplySettingsToOverlay();
    }

    private void SelectColor(string colorName, bool persist)
    {
        if (!_colors.TryGetValue(colorName, out _))
        {
            return;
        }

        _settings.ColorName = colorName;
        _previewColorName = null;
        ApplySettingsToOverlay();
        if (persist)
        {
            SaveSettings();
        }
    }

    private void SelectBarShape(BarShape shape, bool persist)
    {
        _settings.BarShape = shape;
        ApplySettingsToOverlay();
        if (persist)
        {
            SaveSettings();
        }
    }

    private void SelectBarOrientation(BarOrientation orientation, bool persist)
    {
        _settings.BarOrientation = orientation;
        ApplySettingsToOverlay();
        if (persist)
        {
            SaveSettings();
        }
    }

    private void SelectHighlightMode(HighlightMode mode, bool persist)
    {
        _settings.Mode = mode;
        ApplySettingsToOverlay();
        if (persist)
        {
            SaveSettings();
        }
    }

    private void ApplyProfile(Profile profile, bool persist)
    {
        // Copy all settings from the profile
        _settings.FontReferenceSize = profile.Settings.FontReferenceSize;
        _settings.BarOpacityPercent = profile.Settings.BarOpacityPercent;
        _settings.ColorName = profile.Settings.ColorName;
        _settings.IsLocked = profile.Settings.IsLocked;
        _settings.LockedAnchorX = profile.Settings.LockedAnchorX;
        _settings.LockedAnchorY = profile.Settings.LockedAnchorY;
        _settings.Mode = profile.Settings.Mode;
        _settings.SpotlightColorName = profile.Settings.SpotlightColorName;
        _settings.SpotlightOpacityPercent = profile.Settings.SpotlightOpacityPercent;
        _settings.TintColorName = profile.Settings.TintColorName;
        _settings.TintOpacityPercent = profile.Settings.TintOpacityPercent;
        _settings.BarShape = profile.Settings.BarShape;
        _settings.BarOrientation = profile.Settings.BarOrientation;
        _settings.TrackingSource = profile.Settings.TrackingSource;

        ApplySettingsToOverlay();

        if (persist)
        {
            SaveSettings();
            if (!profile.IsBuiltIn)
            {
                _profileStore.SetLastAppliedName(profile.Name);
            }
        }
    }

    private void ApplySettingsToOverlay()
    {
        var color = _colors.TryGetValue(_settings.ColorName, out var selectedColor)
            ? selectedColor
            : _colors["Yellow"];

        _overlay.SetHeightFromFontReference(_settings.FontReferenceSize);
        _overlay.SetBarShape(_settings.BarShape);
        _overlay.SetBarOrientation(_settings.BarOrientation);
        _overlay.SetAppearance(color, _settings.BarOpacityPercent);
        UpdateLockState();
        _overlay.FollowCursor(Cursor.Position);
        UpdateOverlays();
        UpdateMenuLabels();
        UpdateColorChecks();
        UpdateModeChecks();
        UpdateShapeChecks();
        UpdateOrientationChecks();
    }

    private void UpdateOverlays()
    {
        // Hide all screen tint overlays
        foreach (var overlay in _screenTintOverlays)
        {
            overlay.Hide();
        }

        // Hide spotlight overlay
        _spotlightOverlay?.Hide();

        if (_barHidden)
        {
            return;
        }

        // Show overlays based on mode
        if (_settings.Mode == HighlightMode.ScreenTint)
        {
            ShowScreenTintOverlay();
        }
        else if (_settings.Mode == HighlightMode.BarAndSpotlight)
        {
            ShowSpotlightOverlay();
        }
    }

    private void ShowScreenTintOverlay()
    {
        // Dispose existing overlays
        foreach (var overlay in _screenTintOverlays)
        {
            overlay.Dispose();
        }
        _screenTintOverlays.Clear();

        var tintColor = _colors.TryGetValue(_settings.TintColorName, out var selectedTintColor)
            ? selectedTintColor
            : _colors["Yellow"];

        // Create one overlay per monitor
        foreach (var screen in Screen.AllScreens)
        {
            var overlay = new ScreenTintOverlayForm(screen);
            overlay.SetTintColor(tintColor);
            overlay.SetOpacity(_settings.TintOpacityPercent);
            overlay.Show();
            _screenTintOverlays.Add(overlay);
        }
    }

    private void ShowSpotlightOverlay()
    {
        // Dispose existing overlays
        _spotlightOverlay?.Dispose();
        _spotlightOverlay = null;

        var dimColor = _colors.TryGetValue(_settings.SpotlightColorName, out var selectedDimColor)
            ? selectedDimColor
            : _colors["Gray"];

        // Create one overlay per monitor
        // For now, create one overlay on the monitor where the bar is
        var barScreen = Screen.FromPoint(_overlay.Location);
        var overlay = new SpotlightOverlayForm(barScreen);
        overlay.SetDimOpacity(_settings.SpotlightOpacityPercent);

        // Get bar position and size to calculate spotlight rectangle
        var barBounds = _overlay.Bounds;
        var spotlightRect = new Rectangle(
            barBounds.X - barScreen.Bounds.X,  // Relative to overlay's monitor
            barBounds.Y - barScreen.Bounds.Y,
            barBounds.Width,
            barBounds.Height
        );

        overlay.SetSpotlight(spotlightRect, dimColor);
        overlay.Show();
        _spotlightOverlay = overlay;
    }

    private void UpdateSpotlightPosition()
    {
        // Update spotlight position if it's active
        if (_settings.Mode == HighlightMode.BarAndSpotlight && _spotlightOverlay != null && !_barHidden)
        {
            var barBounds = _overlay.Bounds;
            var barScreen = Screen.FromPoint(barBounds.Location);

            var spotlightRect = new Rectangle(
                barBounds.X - barScreen.Bounds.X,
                barBounds.Y - barScreen.Bounds.Y,
                barBounds.Width,
                barBounds.Height
            );

            _spotlightOverlay.SetSpotlight(spotlightRect, Color.Gray);
        }
    }

    private void NormalizeSettings()
    {
        _settings.FontReferenceSize = Math.Clamp(_settings.FontReferenceSize, 10, 100);
        _settings.BarOpacityPercent = Math.Clamp(_settings.BarOpacityPercent, 10, 90);

        if (!_colors.ContainsKey(_settings.ColorName))
        {
            _settings.ColorName = "Yellow";
        }

        // Sync registry with saved settings
        _settings.LaunchAtLogin = RegistryUtil.IsLaunchAtStartupEnabled();
    }

    private void SaveSettings()
    {
        SettingsStore.Save(_settings);
    }

    private void ToggleVisibility()
    {
        _barHidden = !_barHidden;
        if (_barHidden)
        {
            _overlay.Hide();
            foreach (var overlay in _screenTintOverlays)
            {
                overlay.Hide();
            }
            _spotlightOverlay?.Hide();
        }
        else
        {
            _overlay.Show();
            _overlay.FollowCursor(Cursor.Position);
            UpdateOverlays();
        }

        _visibilityItem.Text = _barHidden ? "Show Bar (Ctrl+Shift+H)" : "Hide Bar (Ctrl+Shift+H)";
    }

    private void ToggleLock()
    {
        _settings.IsLocked = !_settings.IsLocked;

        if (_settings.IsLocked)
        {
            // Lock at current cursor position
            _lockAnchorPoint = Cursor.Position;
            _settings.LockedAnchorX = _lockAnchorPoint.X;
            _settings.LockedAnchorY = _lockAnchorPoint.Y;
        }
        else
        {
            // Unlock and clear the anchor
            _settings.LockedAnchorX = null;
            _settings.LockedAnchorY = null;
        }

        UpdateLockState();
        SaveSettings();
    }

    private void UpdateLockState()
    {
        _lockItem.Checked = _settings.IsLocked;
        _lockItem.Text = _settings.IsLocked ? "Unlock Position (Ctrl+Shift+L)" : "Lock Position (Ctrl+Shift+L)";

        // Apply lock state to overlay
        Point? lockedPos = null;
        if (_settings.IsLocked && _settings.LockedAnchorX.HasValue && _settings.LockedAnchorY.HasValue)
        {
            lockedPos = new Point((int)_settings.LockedAnchorX.Value, (int)_settings.LockedAnchorY.Value);
        }

        _overlay.SetLockedPosition(_settings.IsLocked, lockedPos);
    }

    private void ToggleStartup()
    {
        _settings.LaunchAtLogin = !_settings.LaunchAtLogin;

        // Write to Windows registry
        RegistryUtil.SetLaunchAtStartup(_settings.LaunchAtLogin);

        UpdateStartupState();
        SaveSettings();
    }

    private void UpdateStartupState()
    {
        _startupItem.Checked = _settings.LaunchAtLogin;
    }

    private void OnDisplayChanged()
    {
        // Re-apply overlay positioning when display configuration changes
        if (!_barHidden)
        {
            _overlay.FollowCursor(Cursor.Position);
        }
    }

    private void Nudge(int delta)
    {
        // Only nudge when locked
        if (!_settings.IsLocked)
        {
            return;
        }

        if (_settings.BarOrientation == BarOrientation.Vertical)
        {
            // For vertical mode, nudge affects X
            if (!_settings.LockedAnchorX.HasValue)
            {
                return;
            }

            var newX = (int)_settings.LockedAnchorX.Value + delta;
            _settings.LockedAnchorX = newX;
        }
        else
        {
            // For horizontal mode, nudge affects Y
            if (!_settings.LockedAnchorY.HasValue)
            {
                return;
            }

            var newY = (int)_settings.LockedAnchorY.Value + delta;
            _settings.LockedAnchorY = newY;
        }

        UpdateLockState();
        SaveSettings();
    }

    private void OnScroll(ScrollEventArgs e)
    {
        // Only process scroll when tracking source is Scroll
        if (_barHidden || _settings.TrackingSource != TrackingSource.Scroll)
        {
            return;
        }

        // Accumulate scroll delta (each notch is 120)
        _scrollAccumulation += e.Delta;

        // Convert scroll accumulation to pixels (roughly 20 pixels per notch)
        var barPosition = new Point(
            Cursor.Position.X,
            Cursor.Position.Y + (_scrollAccumulation / 120) * 20
        );

        _overlay.FollowCursor(barPosition);

        // Reset the settle timer
        _scrollSettleTimer?.Stop();
        _scrollSettleTimer = new System.Windows.Forms.Timer { Interval = 100 };
        _scrollSettleTimer.Tick += (_, _) =>
        {
            // Reset accumulation after scroll settles
            _scrollAccumulation = 0;
            _scrollSettleTimer.Stop();
        };
        _scrollSettleTimer.Start();
    }

    private void OnKeyboard(KeyboardTrackingEventArgs e)
    {
        // Only process keyboard when tracking source is Keyboard and not locked
        if (_barHidden || _settings.TrackingSource != TrackingSource.Keyboard || _settings.IsLocked)
        {
            return;
        }

        // Determine offset direction based on orientation and key code
        var offset = new Point(0, 0);
        const int VK_UP = 0x26;
        const int VK_DOWN = 0x28;
        const int VK_LEFT = 0x25;
        const int VK_RIGHT = 0x27;

        if (_settings.BarOrientation == BarOrientation.Horizontal)
        {
            // For horizontal bar, use up/down arrow keys
            if (e.KeyCode == VK_UP)
                offset = new Point(Cursor.Position.X, Cursor.Position.Y - 20);
            else if (e.KeyCode == VK_DOWN)
                offset = new Point(Cursor.Position.X, Cursor.Position.Y + 20);
        }
        else
        {
            // For vertical bar, use left/right arrow keys
            if (e.KeyCode == VK_LEFT)
                offset = new Point(Cursor.Position.X - 20, Cursor.Position.Y);
            else if (e.KeyCode == VK_RIGHT)
                offset = new Point(Cursor.Position.X + 20, Cursor.Position.Y);
        }

        // Only move if we determined a valid direction
        if (offset != Point.Empty)
        {
            _overlay.FollowCursor(offset);
        }
    }

    private void OnHotKeyConflict(HotKeyConflictEventArgs e)
    {
        // Only show alert once per session
        if (_settings.HasShownHotKeyConflictAlert)
        {
            return;
        }

        var message = "Some Highlight Bar hotkeys are already in use by another application:\n\n" +
                      e.ConflictDescription + "\n\n" +
                      "You can still use the system tray menu to control the highlight bar.";

        MessageBox.Show(message, "Hotkey Conflict", MessageBoxButtons.OK, MessageBoxIcon.Information);

        _settings.HasShownHotKeyConflictAlert = true;
        SaveSettings();
    }

    private void ExitApp()
    {
        _followTimer.Stop();
        _scrollSettleTimer?.Stop();
        foreach (var overlay in _screenTintOverlays)
        {
            overlay.Dispose();
        }
        _spotlightOverlay?.Dispose();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _overlay.Close();
        ExitThread();
    }
}
