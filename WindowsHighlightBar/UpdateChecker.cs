using System.Diagnostics;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace HighlightBar.Windows;

/// <summary>
/// Checks for updates from GitHub releases API.
/// Provides version comparison and download information.
/// </summary>
public sealed class UpdateChecker
{
    private const string GitHubApiUrl = "https://api.github.com/repos/25mattm/Highlighter/releases/latest";
    private const string CurrentVersion = "1.0.1";  // Should match app version
    private static readonly HttpClient _httpClient = new()
    {
        DefaultRequestHeaders =
        {
            { "User-Agent", "HighlightBar-Windows" }
        }
    };

    /// <summary>
    /// Check if an update is available.
    /// </summary>
    public static async Task<bool> IsUpdateAvailable()
    {
        try
        {
            var latestVersion = await GetLatestVersion();
            return latestVersion != null && IsNewerVersion(latestVersion, CurrentVersion);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Get the latest release information from GitHub.
    /// </summary>
    public static async Task<UpdateInfo?> GetLatestUpdateInfo()
    {
        try
        {
            var response = await _httpClient.GetStringAsync(GitHubApiUrl);
            using (var doc = JsonDocument.Parse(response))
            {
                var root = doc.RootElement;

                var version = root.GetProperty("tag_name").GetString();
                var name = root.GetProperty("name").GetString();
                var body = root.GetProperty("body").GetString();
                var htmlUrl = root.GetProperty("html_url").GetString();

                if (version == null || name == null)
                    return null;

                // Extract download URL from assets
                string? downloadUrl = null;
                if (root.TryGetProperty("assets", out var assets) && assets.ValueKind == JsonValueKind.Array)
                {
                    foreach (var asset in assets.EnumerateArray())
                    {
                        if (asset.TryGetProperty("name", out var assetName) &&
                            assetName.GetString()?.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) == true)
                        {
                            if (asset.TryGetProperty("browser_download_url", out var url))
                            {
                                downloadUrl = url.GetString();
                                break;
                            }
                        }
                    }
                }

                return new UpdateInfo
                {
                    Version = version,
                    Name = name,
                    Notes = body ?? string.Empty,
                    DownloadUrl = downloadUrl,
                    ReleaseUrl = htmlUrl ?? string.Empty
                };
            }
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Get the latest version string from GitHub.
    /// </summary>
    private static async Task<string?> GetLatestVersion()
    {
        try
        {
            var response = await _httpClient.GetStringAsync(GitHubApiUrl);
            using (var doc = JsonDocument.Parse(response))
            {
                return doc.RootElement.GetProperty("tag_name").GetString()?.TrimStart('v');
            }
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Compare two semantic versions.
    /// </summary>
    private static bool IsNewerVersion(string latestVersion, string currentVersion)
    {
        try
        {
            var latest = Version.Parse(latestVersion.TrimStart('v'));
            var current = Version.Parse(currentVersion);
            return latest > current;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Launch browser to download/view update.
    /// </summary>
    public static void OpenUpdatePage(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch
        {
            // Silently fail if unable to open browser
        }
    }
}

/// <summary>
/// Information about an available update.
/// </summary>
public sealed class UpdateInfo
{
    public string Version { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Notes { get; set; } = string.Empty;
    public string DownloadUrl { get; set; } = string.Empty;
    public string ReleaseUrl { get; set; } = string.Empty;
}
