using System.Drawing;
using System.Windows.Forms;

namespace HighlightBar.Windows;

/// <summary>
/// A welcome window shown on first launch explaining hotkeys and features.
/// Designed with accessibility: keyboard navigation, screen reader support.
/// </summary>
internal sealed class OnboardingForm : Form
{
    private bool _dismissed = false;

    public OnboardingForm()
    {
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        ShowInTaskbar = true;
        MaximizeBox = false;
        MinimizeBox = false;
        Width = 500;
        Height = 450;
        Text = "Welcome to Highlight Bar";
        ShowIcon = true;

        // Set accessible name for the form for screen readers
        AccessibleName = "Welcome to Highlight Bar";
        AccessibleDescription = "First-run onboarding screen explaining how to use Highlight Bar";

        var titleLabel = new Label
        {
            Text = "Highlight Bar",
            Font = new Font(SystemFonts.DefaultFont.FontFamily, 16, FontStyle.Bold),
            AutoSize = true,
            Location = new Point(20, 20),
            TabStop = false
        };
        titleLabel.AccessibleName = "Highlight Bar";
        titleLabel.AccessibleRole = AccessibleRole.TitleBar;

        var bodyText =
            "Highlight Bar is a reading guide that follows your cursor and stays on top of every window — and it is fully click-through, so it never blocks clicks, scrolling, or typing.\r\n\r\n" +
            "•  Show or hide everything with Ctrl+Shift+H.\r\n" +
            "•  Lock the bar in place with Ctrl+Shift+L, then nudge it with Ctrl+Shift+↑ / ↓.\r\n" +
            "•  Use the system tray menu to change size, color, opacity, display mode, shape, tracking, and one-tap profiles.\r\n\r\n" +
            "Everything stays on your PC — no sign-in, no network, no data collection.";

        var bodyLabel = new Label
        {
            Text = bodyText,
            Font = SystemFonts.DefaultFont,
            AutoSize = false,
            Dock = DockStyle.None,
            Location = new Point(20, 60),
            Width = 460,
            Height = 300,
            TabStop = false
        };
        bodyLabel.AccessibleName = "Features and hotkeys information";
        bodyLabel.AccessibleRole = AccessibleRole.StaticText;

        var okButton = new Button
        {
            Text = "Got it",
            DialogResult = DialogResult.OK,
            Location = new Point(405, 375),
            Width = 75,
            Height = 30
        };
        okButton.Click += (_, _) => _dismissed = true;
        okButton.AccessibleName = "Got it (dismiss welcome)";
        okButton.AccessibleDescription = "Dismiss the welcome screen and start using Highlight Bar";
        okButton.TabIndex = 0;

        Controls.Add(titleLabel);
        Controls.Add(bodyLabel);
        Controls.Add(okButton);

        AcceptButton = okButton;
        CancelButton = okButton;
    }

    public bool WasDismissed => _dismissed;
}
