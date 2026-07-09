namespace HighlightBar.Windows;

/// <summary>
/// Display mode enumeration: bar visibility and overlay type.
/// </summary>
public enum HighlightMode
{
    Off,
    BarOnly,
    BarAndSpotlight,
    ScreenTint
}

/// <summary>
/// Bar shape: ruler (band) or line (thin).
/// </summary>
public enum BarShape
{
    Ruler,
    Line
}

/// <summary>
/// Bar orientation: horizontal (follows Y) or vertical (follows X).
/// </summary>
public enum BarOrientation
{
    Horizontal,
    Vertical
}

/// <summary>
/// What drives the bar's position: mouse, scroll wheel, or keyboard.
/// </summary>
public enum TrackingSource
{
    Mouse,
    Scroll,
    Keyboard
}

/// <summary>
/// The single source of truth for all user-configurable settings.
/// Mirrors the macOS Settings.swift structure for parity.
/// 
/// Note: Opacity is stored as a percentage (10-90) for the Windows UI,
/// but serialized as a double (0.1-0.9) for JSON compatibility with macOS.
/// </summary>
public sealed class AppSettings
{
    // Basic appearance (shared baseline)
    public int FontReferenceSize { get; set; } = 22;

    /// <summary>
    /// Bar opacity as a percentage (10-90). Internally used in the Windows UI.
    /// </summary>
    public int BarOpacityPercent { get; set; } = 35;

    public string ColorName { get; set; } = "Yellow";

    // Lock mode (Phase 2)
    public bool IsLocked { get; set; } = false;
    public double? LockedAnchorX { get; set; }
    public double? LockedAnchorY { get; set; }

    // Overlay modes (Phase 4)
    public HighlightMode Mode { get; set; } = HighlightMode.BarOnly;
    public string SpotlightColorName { get; set; } = "Gray";
    
    /// <summary>
    /// Spotlight opacity as a percentage (10-90) for UI consistency.
    /// </summary>
    public int SpotlightOpacityPercent { get; set; } = 50;
    
    public string TintColorName { get; set; } = "Yellow";
    
    /// <summary>
    /// Tint opacity as a percentage (10-90) for UI consistency.
    /// </summary>
    public int TintOpacityPercent { get; set; } = 20;

    // Bar shape and tracking (Phase 2-3)
    public BarShape BarShape { get; set; } = BarShape.Ruler;
    public BarOrientation BarOrientation { get; set; } = BarOrientation.Horizontal;
    public TrackingSource TrackingSource { get; set; } = TrackingSource.Mouse;

    // App lifecycle (Phase 6)
    public bool LaunchAtLogin { get; set; } = false;
    public bool HasSeenOnboarding { get; set; } = false;

    // Per-app auto-enable (future)
    public bool PerAppEnabled { get; set; } = false;
    public List<string> EnabledAppExePaths { get; set; } = new();

    // Hotkey conflict alert
    public bool HasShownHotKeyConflictAlert { get; set; } = false;

    public AppSettings()
    {
    }
}
