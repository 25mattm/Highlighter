using Microsoft.Win32;

namespace HighlightBar.Windows;

/// <summary>
/// Utilities for managing Windows registry entries.
/// </summary>
public static class RegistryUtil
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string AppName = "HighlightBar";

    /// <summary>
    /// Check if the app is set to launch at startup.
    /// </summary>
    public static bool IsLaunchAtStartupEnabled()
    {
        try
        {
            using (var key = Registry.CurrentUser.OpenSubKey(RunKeyPath))
            {
                if (key == null)
                {
                    return false;
                }

                var value = key.GetValue(AppName);
                return value != null;
            }
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Enable launching the app at startup.
    /// </summary>
    public static bool SetLaunchAtStartup(bool enabled)
    {
        try
        {
            using (var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true))
            {
                if (key == null)
                {
                    return false;
                }

                if (enabled)
                {
                    // Get the path to the current executable
                    var exePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
                    key.SetValue(AppName, exePath);
                }
                else
                {
                    key.DeleteValue(AppName, throwOnMissing: false);
                }

                return true;
            }
        }
        catch
        {
            return false;
        }
    }
}
