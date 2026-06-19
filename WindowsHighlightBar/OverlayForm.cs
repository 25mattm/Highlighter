using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace HighlightBar.Windows;

internal sealed class OverlayForm : Form
{
    private const int CornerRadius = 10;

    // System-wide Ctrl+Shift+H shortcut to show/hide the bar. RegisterHotKey
    // needs no special permission and posts WM_HOTKEY to this window.
    private const int ToggleHotKeyId = 1;
    private const int WmHotKey = 0x0312;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private const uint ModNoRepeat = 0x4000;
    private const uint VkH = 0x48;

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public event EventHandler? ToggleRequested;

    private int _barHeight = 44;
    private Color _barColor = Color.Gold;
    private int _opacityPercent = 35;

    public OverlayForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        DoubleBuffered = true;
        ResizeRedraw = true;
        BackColor = _barColor;
        Opacity = _opacityPercent / 100.0;
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            const int WsExToolWindow = 0x00000080;
            const int WsExNoActivate = 0x08000000;
            const int WsExLayered = 0x00080000;
            const int WsExTransparent = 0x00000020;

            var createParams = base.CreateParams;
            createParams.ExStyle |= WsExToolWindow | WsExNoActivate | WsExLayered | WsExTransparent;
            return createParams;
        }
    }

    public void SetHeightFromFontReference(int fontReferenceSize)
    {
        _barHeight = Math.Clamp(fontReferenceSize * 2, 18, 200);
    }

    public void SetAppearance(Color color, int opacityPercent)
    {
        _barColor = color;
        _opacityPercent = Math.Clamp(opacityPercent, 10, 90);
        BackColor = _barColor;
        Opacity = _opacityPercent / 100.0;
        Invalidate();
    }

    public void FollowCursor(Point cursorPosition)
    {
        var screen = Screen.FromPoint(cursorPosition);
        var bounds = screen.Bounds;
        var y = cursorPosition.Y - (_barHeight / 2);
        y = Math.Clamp(y, bounds.Top, bounds.Bottom - _barHeight);

        var newBounds = new Rectangle(bounds.Left, y, bounds.Width, _barHeight);
        if (Bounds != newBounds)
        {
            Bounds = newBounds;
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        RegisterHotKey(Handle, ToggleHotKeyId, ModControl | ModShift | ModNoRepeat, VkH);
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        UnregisterHotKey(Handle, ToggleHotKeyId);
        base.OnHandleDestroyed(e);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotKey && m.WParam.ToInt32() == ToggleHotKeyId)
        {
            ToggleRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        base.WndProc(ref m);
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        UpdateRegion();
    }

    private void UpdateRegion()
    {
        using var path = RoundedRectPath(ClientRectangle, CornerRadius);
        Region = new Region(path);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

        // The whole form shares one opacity, so the border is drawn in a darker
        // shade of the bar color to give the rounded outline visible definition
        // (mirrors the higher-opacity border on the macOS app).
        var borderColor = DarkenColor(_barColor, 0.35);
        var borderRect = new Rectangle(0, 0, Width - 1, Height - 1);
        using var path = RoundedRectPath(borderRect, CornerRadius);
        using var pen = new Pen(borderColor, 1.5f);
        e.Graphics.DrawPath(pen, path);
    }

    private static GraphicsPath RoundedRectPath(Rectangle rect, int radius)
    {
        var diameter = Math.Min(radius * 2, Math.Min(rect.Width, rect.Height));
        var path = new GraphicsPath();

        if (diameter <= 0)
        {
            path.AddRectangle(rect);
            path.CloseFigure();
            return path;
        }

        var arc = new Rectangle(rect.Location, new Size(diameter, diameter));
        path.AddArc(arc, 180, 90);
        arc.X = rect.Right - diameter;
        path.AddArc(arc, 270, 90);
        arc.Y = rect.Bottom - diameter;
        path.AddArc(arc, 0, 90);
        arc.X = rect.Left;
        path.AddArc(arc, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static Color DarkenColor(Color color, double amount)
    {
        var factor = 1.0 - Math.Clamp(amount, 0.0, 1.0);
        return Color.FromArgb(
            color.A,
            (int)(color.R * factor),
            (int)(color.G * factor),
            (int)(color.B * factor));
    }
}
