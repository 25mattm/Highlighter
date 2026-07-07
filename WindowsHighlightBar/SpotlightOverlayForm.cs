using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace HighlightBar.Windows;

/// <summary>
/// A fullscreen overlay that dims the screen and reveals a spotlight region matching the bar position.
/// One instance is created per monitor.
/// </summary>
internal sealed class SpotlightOverlayForm : Form
{
    private Color _dimColor = Color.Gray;
    private int _dimOpacityPercent = 50;
    private Rectangle _spotlightRect = Rectangle.Empty;

    public SpotlightOverlayForm(Screen screen)
    {
        // Configure as a transparent, click-through overlay
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;

        // Set to screen bounds
        Left = screen.Bounds.Left;
        Top = screen.Bounds.Top;
        Width = screen.Bounds.Width;
        Height = screen.Bounds.Height;

        // Enable transparency
        TransparencyKey = Color.Magenta;
        BackColor = Color.Magenta;

        // Allow events to pass through to windows below
        SetStyle(ControlStyles.SupportsTransparentBackColor, true);

        // Accessibility
        AccessibleName = "Spotlight overlay";
        AccessibleDescription = "Spotlight overlay that dims the screen and highlights the reading bar area";
        AccessibleRole = AccessibleRole.Window;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        if (_spotlightRect == Rectangle.Empty)
        {
            return;
        }

        // Create a semi-transparent dim brush
        var alpha = (int)(255 * (_dimOpacityPercent / 100.0));
        var dimBrush = new SolidBrush(Color.FromArgb(alpha, _dimColor));

        // Create a path for the entire screen minus the spotlight rectangle
        using (var path = new GraphicsPath())
        {
            // Add the entire client rectangle
            path.AddRectangle(ClientRectangle);

            // Subtract the spotlight rectangle using XOR-like approach
            // We'll fill the entire screen first, then clear the spotlight area
        }

        // Fill entire screen with dim overlay
        e.Graphics.FillRectangle(dimBrush, ClientRectangle);

        // Create a transparent (clear) brush for the spotlight
        using (var clearBrush = new SolidBrush(Color.FromArgb(0, 0, 0, 0)))
        {
            // Clear the spotlight area to reveal what's underneath
            e.Graphics.CompositingMode = CompositingMode.SourceCopy;
            e.Graphics.FillRectangle(clearBrush, _spotlightRect);
            e.Graphics.CompositingMode = CompositingMode.SourceOver;
        }

        dimBrush.Dispose();
    }

    protected override void WndProc(ref Message m)
    {
        const int WM_MOUSEACTIVATE = 0x0021;
        const int MA_NOACTIVATE = 0x0003;
        const int WM_NCHITTEST = 0x0084;
        const int HTTRANSPARENT = -1;

        if (m.Msg == WM_MOUSEACTIVATE)
        {
            // Don't activate this window on mouse click
            m.Result = (IntPtr)MA_NOACTIVATE;
            return;
        }

        if (m.Msg == WM_NCHITTEST)
        {
            // Make the window transparent to mouse events
            m.Result = (IntPtr)HTTRANSPARENT;
            return;
        }

        base.WndProc(ref m);
    }

    public void SetSpotlight(Rectangle spotlightRect, Color dimColor)
    {
        // Convert spotlight rect to screen-relative coordinates
        // _spotlightRect should be in the form's coordinate system (already screen coords for this form's monitor)
        _spotlightRect = spotlightRect;
        _dimColor = dimColor;
        Invalidate();
    }

    public void SetDimOpacity(int opacityPercent)
    {
        _dimOpacityPercent = opacityPercent;
        Invalidate();
    }
}
