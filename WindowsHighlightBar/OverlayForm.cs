using System.Drawing;
using System.Windows.Forms;

namespace HighlightBar.Windows;

internal sealed class OverlayForm : Form
{
    private int _barHeight = 44;
    private Color _barColor = Color.Gold;
    private int _opacityPercent = 35;

    public OverlayForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
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
}
