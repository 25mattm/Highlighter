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

    private string? _previewColorName;

    public TrayApplicationContext()
    {
        _settings = SettingsStore.Load();
        NormalizeSettings();

        _overlay = new OverlayForm();
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

        _followTimer = new System.Windows.Forms.Timer { Interval = 16 };
        _followTimer.Tick += (_, _) => _overlay.FollowCursor(Cursor.Position);
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

        var decreaseOpacityItem = new ToolStripMenuItem("Lower Transparency (-5%)", null, (_, _) => ChangeOpacity(-5));
        var increaseOpacityItem = new ToolStripMenuItem("Higher Transparency (+5%)", null, (_, _) => ChangeOpacity(5));

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

        var quitItem = new ToolStripMenuItem("Quit Highlight Bar", null, (_, _) => ExitApp());

        menu.Items.Add(decreaseFontItem);
        menu.Items.Add(increaseFontItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(decreaseOpacityItem);
        menu.Items.Add(increaseOpacityItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(colorHeader);
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
        _opacityLabelItem.Text = $"Transparency: {_settings.OpacityPercent}%";
    }

    private void UpdateColorChecks()
    {
        foreach (var (name, item) in _colorMenuItems)
        {
            item.Checked = name.Equals(_settings.ColorName, StringComparison.OrdinalIgnoreCase);
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
        _settings.OpacityPercent = Math.Clamp(_settings.OpacityPercent + deltaPercent, 10, 90);
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

    private void ExitApp()
    {
        _followTimer.Stop();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _overlay.Close();
        ExitThread();
    }
}
