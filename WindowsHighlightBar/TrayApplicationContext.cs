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
    private readonly OverlayForm _overlay;
    private readonly NotifyIcon _notifyIcon;
    private readonly System.Windows.Forms.Timer _followTimer;
    private readonly AppSettings _settings;
    private readonly ToolStripMenuItem _fontLabelItem = new() { Enabled = false };
    private readonly ToolStripMenuItem _opacityLabelItem = new() { Enabled = false };
    private readonly ToolStripMenuItem _visibilityItem = new("Hide Bar (Ctrl+Shift+H)");
    private readonly ToolStripMenuItem _lockItem = new("Lock Position");

    private string? _previewColorName;
    private bool _barHidden;
    private Point _lockAnchorPoint;

    public TrayApplicationContext()
    {
        _settings = SettingsStore.Load();
        NormalizeSettings();

        _overlay = new OverlayForm();
        _overlay.ToggleRequested += (_, _) => ToggleVisibility();
        _overlay.LockToggleRequested += (_, _) => ToggleLock();
        _overlay.NudgeUpRequested += (_, _) => Nudge(delta: -10);
        _overlay.NudgeDownRequested += (_, _) => Nudge(delta: 10);
        _overlay.DisplayChanged += (_, _) => OnDisplayChanged();
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

        _followTimer = new System.Windows.Forms.Timer { Interval = 16 };
        _followTimer.Tick += (_, _) =>
        {
            if (!_barHidden)
            {
                _overlay.FollowCursor(Cursor.Position);
            }
        };
        _followTimer.Start();
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

        _lockItem.Click += (_, _) => ToggleLock();
        _visibilityItem.Click += (_, _) => ToggleVisibility();

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
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_lockItem);
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

        foreach (var (shape, item) in _barShapeMenuItems)
        {
            item.Checked = shape == _settings.BarShape;
        }

        foreach (var (orientation, item) in _barOrientationMenuItems)
        {
            item.Checked = orientation == _settings.BarOrientation;
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
        UpdateMenuLabels();
        UpdateColorChecks();
    }

    private void NormalizeSettings()
    {
        _settings.FontReferenceSize = Math.Clamp(_settings.FontReferenceSize, 10, 100);
        _settings.BarOpacityPercent = Math.Clamp(_settings.BarOpacityPercent, 10, 90);

        if (!_colors.ContainsKey(_settings.ColorName))
        {
            _settings.ColorName = "Yellow";
        }
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
        }
        else
        {
            _overlay.Show();
            _overlay.FollowCursor(Cursor.Position);
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

    private void ExitApp()
    {
        _followTimer.Stop();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _overlay.Close();
        ExitThread();
    }
}
