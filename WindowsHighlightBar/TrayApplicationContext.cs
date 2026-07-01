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
    private readonly OverlayForm _overlay;
    private readonly NotifyIcon _notifyIcon;
    private readonly System.Windows.Forms.Timer _followTimer;
    private readonly AppSettings _settings;
    private readonly ToolStripMenuItem _fontLabelItem = new() { Enabled = false };
    private readonly ToolStripMenuItem _opacityLabelItem = new() { Enabled = false };
    private readonly ToolStripMenuItem _visibilityItem = new("Hide Bar (Ctrl+Shift+H)");
    private readonly TrackBar _fontTrackBar;
    private readonly TrackBar _opacityTrackBar;
    private readonly ToolStripControlHost _fontSliderItem;
    private readonly ToolStripControlHost _opacitySliderItem;

    private string? _previewColorName;
    private bool _barHidden;

    public TrayApplicationContext()
    {
        _settings = SettingsStore.Load();
        NormalizeSettings();

        _fontTrackBar = CreateTrackBar(
            minValue: 10,
            maxValue: 100,
            tickFrequency: 10,
            initialValue: _settings.FontReferenceSize,
            onScroll: value => SetFontReference(value, persist: true));
        _fontSliderItem = CreateTrackBarHost(_fontTrackBar);

        _opacityTrackBar = CreateTrackBar(
            minValue: 10,
            maxValue: 90,
            tickFrequency: 5,
            initialValue: _settings.OpacityPercent,
            onScroll: value => SetOpacity(value, persist: true));
        _opacitySliderItem = CreateTrackBarHost(_opacityTrackBar);

        _overlay = new OverlayForm();
        _overlay.ToggleRequested += (_, _) => ToggleVisibility();
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

        UpdateMenuLabels();
        UpdateColorChecks();
        SyncSliderValues();

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

        _visibilityItem.Click += (_, _) => ToggleVisibility();

        var quitItem = new ToolStripMenuItem("Quit Highlight Bar", null, (_, _) => ExitApp());

        menu.Items.Add(_fontLabelItem);
        menu.Items.Add(_fontSliderItem);
        menu.Items.Add(decreaseFontItem);
        menu.Items.Add(increaseFontItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_opacityLabelItem);
        menu.Items.Add(_opacitySliderItem);
        menu.Items.Add(decreaseOpacityItem);
        menu.Items.Add(increaseOpacityItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(colorHeader);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_visibilityItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(quitItem);

        return menu;
    }

    private static TrackBar CreateTrackBar(int minValue, int maxValue, int tickFrequency, int initialValue, Action<int> onScroll)
    {
        var trackBar = new TrackBar
        {
            Minimum = minValue,
            Maximum = maxValue,
            TickFrequency = tickFrequency,
            SmallChange = 1,
            LargeChange = tickFrequency,
            AutoSize = false,
            Height = 32,
            Width = 228,
            Value = Math.Clamp(initialValue, minValue, maxValue)
        };

        trackBar.Scroll += (_, _) => onScroll(trackBar.Value);
        return trackBar;
    }

    private static ToolStripControlHost CreateTrackBarHost(TrackBar trackBar)
    {
        var panel = new Panel
        {
            Width = 260,
            Height = 44,
            Margin = Padding.Empty,
            Padding = new Padding(12, 6, 12, 6)
        };

        trackBar.Location = new Point(12, 6);
        panel.Controls.Add(trackBar);

        return new ToolStripControlHost(panel)
        {
            AutoSize = false,
            Margin = Padding.Empty,
            Padding = Padding.Empty,
            Size = panel.Size
        };
    }

    private void UpdateMenuLabels()
    {
        _fontLabelItem.Text = $"Height: {_settings.FontReferenceSize * 2}px ({_settings.FontReferenceSize}pt reference)";
        _opacityLabelItem.Text = $"Opacity: {_settings.OpacityPercent}% ({100 - _settings.OpacityPercent}% transparent)";
    }

    private void UpdateColorChecks()
    {
        foreach (var (name, item) in _colorMenuItems)
        {
            item.Checked = name.Equals(_settings.ColorName, StringComparison.OrdinalIgnoreCase);
        }
    }

    private void SyncSliderValues()
    {
        _fontTrackBar.Value = Math.Clamp(_settings.FontReferenceSize, _fontTrackBar.Minimum, _fontTrackBar.Maximum);
        _opacityTrackBar.Value = Math.Clamp(_settings.OpacityPercent, _opacityTrackBar.Minimum, _opacityTrackBar.Maximum);
    }

    private void ChangeFontReference(int delta)
    {
        SetFontReference(_settings.FontReferenceSize + delta, persist: true);
    }

    private void ChangeOpacity(int deltaPercent)
    {
        SetOpacity(_settings.OpacityPercent + deltaPercent, persist: true);
    }

    private void SetFontReference(int value, bool persist)
    {
        _settings.FontReferenceSize = Math.Clamp(value, 10, 100);
        ApplySettingsToOverlay();
        if (persist)
        {
            SaveSettings();
        }
    }

    private void SetOpacity(int value, bool persist)
    {
        _settings.OpacityPercent = Math.Clamp(value, 10, 90);
        ApplySettingsToOverlay();
        if (persist)
        {
            SaveSettings();
        }
    }

    private void PreviewColor(string colorName)
    {
        if (!_colors.TryGetValue(colorName, out var color))
        {
            return;
        }

        _previewColorName = colorName;
        _overlay.SetAppearance(color, _settings.OpacityPercent);
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

    private void ApplySettingsToOverlay()
    {
        var color = _colors.TryGetValue(_settings.ColorName, out var selectedColor)
            ? selectedColor
            : _colors["Yellow"];

        _overlay.SetHeightFromFontReference(_settings.FontReferenceSize);
        _overlay.SetAppearance(color, _settings.OpacityPercent);
        _overlay.FollowCursor(Cursor.Position);
        UpdateMenuLabels();
        UpdateColorChecks();
        SyncSliderValues();
    }

    private void NormalizeSettings()
    {
        _settings.FontReferenceSize = Math.Clamp(_settings.FontReferenceSize, 10, 100);
        _settings.OpacityPercent = Math.Clamp(_settings.OpacityPercent, 10, 90);

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

    private void ExitApp()
    {
        _followTimer.Stop();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _overlay.Close();
        ExitThread();
    }
}
