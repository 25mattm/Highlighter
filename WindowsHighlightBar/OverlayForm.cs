using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace HighlightBar.Windows;

public class HotKeyConflictEventArgs : EventArgs
{
    public string ConflictDescription { get; }

    public HotKeyConflictEventArgs(string description)
    {
        ConflictDescription = description;
    }
}

public class KeyboardTrackingEventArgs : EventArgs
{
    public int KeyCode { get; }

    public KeyboardTrackingEventArgs(int keyCode)
    {
        KeyCode = keyCode;
    }
}

internal sealed class OverlayForm : Form
{
    private const int CornerRadius = 10;

    // System-wide hotkeys
    private const int ToggleHotKeyId = 1;
    private const int LockHotKeyId = 2;
    private const int NudgeUpHotKeyId = 3;
    private const int NudgeDownHotKeyId = 4;
    private const int WmHotKey = 0x0312;
    private const int WmDisplayChange = 0x007E;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private const uint ModNoRepeat = 0x4000;
    private const uint VkH = 0x48;
    private const uint VkL = 0x4C;
    private const uint VkUp = 0x26;
    private const uint VkDown = 0x28;

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll")]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll")]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    private const int WH_MOUSE_LL = 14;
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_MOUSEWHEEL = 0x020A;
    private const int WM_KEYDOWN = 0x0100;
    private const int VK_UP = 0x26;
    private const int VK_DOWN = 0x28;
    private const int VK_LEFT = 0x25;
    private const int VK_RIGHT = 0x27;

    private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);
    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT
    {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    public event EventHandler? ToggleRequested;
    public event EventHandler? LockToggleRequested;
    public event EventHandler? NudgeUpRequested;
    public event EventHandler? NudgeDownRequested;
    public event EventHandler? DisplayChanged;
    public event EventHandler<ScrollEventArgs>? ScrollRequested;
    public event EventHandler<KeyboardTrackingEventArgs>? KeyboardTrackingRequested;
    public event EventHandler<HotKeyConflictEventArgs>? HotKeyConflictDetected;

    private int _barHeight = 44;
    private BarShape _barShape = BarShape.Ruler;
    private BarOrientation _barOrientation = BarOrientation.Horizontal;
    private Color _barColor = Color.Gold;
    private int _opacityPercent = 35;
    private Point _lastCursorPosition;
    private bool _isLocked = false;
    private Point _lockedPosition;
    private IntPtr _mouseHookHandle = IntPtr.Zero;
    private IntPtr _keyboardHookHandle = IntPtr.Zero;
    private LowLevelMouseProc? _mouseHookDelegate;
    private LowLevelKeyboardProc? _keyboardHookDelegate;

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

    public void SetBarShape(BarShape shape)
    {
        _barShape = shape;
        Invalidate();
    }

    public void SetBarOrientation(BarOrientation orientation)
    {
        _barOrientation = orientation;
        Invalidate();
    }

    public void SetAppearance(Color color, int opacityPercent)
    {
        _barColor = color;
        _opacityPercent = Math.Clamp(opacityPercent, 10, 90);
        BackColor = _barColor;
        Opacity = _opacityPercent / 100.0;
        Invalidate();
    }

    public void SetLockedPosition(bool isLocked, Point? lockedPosition = null)
    {
        _isLocked = isLocked;
        if (isLocked && lockedPosition.HasValue)
        {
            _lockedPosition = lockedPosition.Value;
        }
    }

    public void FollowCursor(Point cursorPosition)
    {
        _lastCursorPosition = cursorPosition;

        // If locked, use the locked position instead
        if (_isLocked)
        {
            ReclampPositionToScreen(_lockedPosition);
            return;
        }

        ReclampPositionToScreen(cursorPosition);
    }

    private void ReclampPositionToScreen(Point cursorPosition)
    {
        var screen = Screen.FromPoint(cursorPosition);
        var bounds = screen.Bounds;

        if (_barOrientation == BarOrientation.Vertical)
        {
            // For vertical mode: bar follows cursor X, spans screen height
            var x = cursorPosition.X - (_barHeight / 2);
            x = Math.Clamp(x, bounds.Left, bounds.Right - _barHeight);
            var newBounds = new Rectangle(x, bounds.Top, _barHeight, bounds.Height);
            if (Bounds != newBounds)
            {
                Bounds = newBounds;
            }
        }
        else
        {
            // For horizontal mode: bar follows cursor Y, spans screen width (default)
            var y = cursorPosition.Y - (_barHeight / 2);
            y = Math.Clamp(y, bounds.Top, bounds.Bottom - _barHeight);
            var newBounds = new Rectangle(bounds.Left, y, bounds.Width, _barHeight);
            if (Bounds != newBounds)
            {
                Bounds = newBounds;
            }
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);

        var conflicts = new List<string>();

        // Register hotkeys and track any failures
        if (!RegisterHotKey(Handle, ToggleHotKeyId, ModControl | ModShift | ModNoRepeat, VkH))
            conflicts.Add("Ctrl+Shift+H (Toggle)");

        if (!RegisterHotKey(Handle, LockHotKeyId, ModControl | ModShift | ModNoRepeat, VkL))
            conflicts.Add("Ctrl+Shift+L (Lock)");

        if (!RegisterHotKey(Handle, NudgeUpHotKeyId, ModControl | ModShift | ModNoRepeat, VkUp))
            conflicts.Add("Ctrl+Shift+↑ (Nudge up)");

        if (!RegisterHotKey(Handle, NudgeDownHotKeyId, ModControl | ModShift | ModNoRepeat, VkDown))
            conflicts.Add("Ctrl+Shift+↓ (Nudge down)");

        // Notify about conflicts if any occurred
        if (conflicts.Count > 0)
        {
            var description = string.Join("\n", conflicts);
            HotKeyConflictDetected?.Invoke(this, new HotKeyConflictEventArgs(description));
        }

        // Set up low-level hooks for input tracking
        var module = GetModuleHandle(null);

        _mouseHookDelegate = MouseHookCallback;
        _mouseHookHandle = SetWindowsHookEx(WH_MOUSE_LL, _mouseHookDelegate, module, 0);

        _keyboardHookDelegate = KeyboardHookCallback;
        _keyboardHookHandle = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardHookDelegate, module, 0);
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        UnregisterHotKey(Handle, ToggleHotKeyId);
        UnregisterHotKey(Handle, LockHotKeyId);
        UnregisterHotKey(Handle, NudgeUpHotKeyId);
        UnregisterHotKey(Handle, NudgeDownHotKeyId);

        // Unhook input hooks
        if (_mouseHookHandle != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_mouseHookHandle);
            _mouseHookHandle = IntPtr.Zero;
        }

        if (_keyboardHookHandle != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_keyboardHookHandle);
            _keyboardHookHandle = IntPtr.Zero;
        }

        base.OnHandleDestroyed(e);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotKey)
        {
            var hotKeyId = m.WParam.ToInt32();
            if (hotKeyId == ToggleHotKeyId)
            {
                ToggleRequested?.Invoke(this, EventArgs.Empty);
                return;
            }

            if (hotKeyId == LockHotKeyId)
            {
                LockToggleRequested?.Invoke(this, EventArgs.Empty);
                return;
            }

            if (hotKeyId == NudgeUpHotKeyId)
            {
                NudgeUpRequested?.Invoke(this, EventArgs.Empty);
                return;
            }

            if (hotKeyId == NudgeDownHotKeyId)
            {
                NudgeDownRequested?.Invoke(this, EventArgs.Empty);
                return;
            }
        }

        if (m.Msg == WmDisplayChange)
        {
            // Display configuration has changed (resolution, monitor plug/unplug, etc.)
            // Re-clamp the bar position on the current screen
            DisplayChanged?.Invoke(this, EventArgs.Empty);
            FollowCursor(_lastCursorPosition);
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

        if (_barShape == BarShape.Line)
        {
            // For line mode, draw a thin line at the center
            var lineY = Height / 2;
            var lineColor = _barColor;
            using var pen = new Pen(lineColor, 2f);
            e.Graphics.DrawLine(pen, 0, lineY, Width, lineY);
        }
        else
        {
            // For ruler mode, draw the full band with a border
            var borderColor = DarkenColor(_barColor, 0.35);
            var borderRect = new Rectangle(0, 0, Width - 1, Height - 1);
            using var path = RoundedRectPath(borderRect, CornerRadius);
            using var pen = new Pen(borderColor, 1.5f);
            e.Graphics.DrawPath(pen, path);
        }
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

    private IntPtr MouseHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && wParam == (IntPtr)WM_MOUSEWHEEL)
        {
            try
            {
                var hookStruct = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
                // mouseData high word contains the scroll delta (120 per notch)
                var scrollDelta = (short)((hookStruct.mouseData >> 16) & 0xffff);
                if (scrollDelta != 0)
                {
                    ScrollRequested?.Invoke(this, new ScrollEventArgs(ScrollEventType.SmallIncrement, scrollDelta));
                }
            }
            catch
            {
                // Silently ignore any errors in hook processing
            }
        }

        return CallNextHookEx(_mouseHookHandle, nCode, wParam, lParam);
    }

    private IntPtr KeyboardHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && wParam == (IntPtr)WM_KEYDOWN)
        {
            try
            {
                var hookStruct = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                // Notify about arrow keys for keyboard tracking
                if (hookStruct.vkCode == VK_UP || hookStruct.vkCode == VK_DOWN ||
                    hookStruct.vkCode == VK_LEFT || hookStruct.vkCode == VK_RIGHT)
                {
                    KeyboardTrackingRequested?.Invoke(this, new KeyboardTrackingEventArgs((int)hookStruct.vkCode));
                }
            }
            catch
            {
                // Silently ignore any errors in hook processing
            }
        }

        return CallNextHookEx(_keyboardHookHandle, nCode, wParam, lParam);
    }
}
