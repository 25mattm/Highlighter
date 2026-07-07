using System.Drawing;
using System.Windows.Forms;

namespace HighlightBar.Windows;

/// <summary>
/// A fullscreen transparent overlay that tints the screen with a solid color.
/// One instance is created per monitor.
/// </summary>
internal sealed class ScreenTintOverlayForm : Form
{
    private Color _tintColor = Color.Yellow;
    private int _opacityPercent = 20;

    public ScreenTintOverlayForm(Screen screen)
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
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        // Create a semi-transparent brush with the tint color
        var alpha = (int)(255 * (_opacityPercent / 100.0));
        var tintBrush = new SolidBrush(Color.FromArgb(alpha, _tintColor));

        // Fill the entire client area with the tint
        e.Graphics.FillRectangle(tintBrush, ClientRectangle);
        tintBrush.Dispose();
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

    public void SetTintColor(Color color)
    {
        _tintColor = color;
        Invalidate();
    }

    public void SetOpacity(int opacityPercent)
    {
        _opacityPercent = opacityPercent;
        Invalidate();
    }
}
