using System.Text.Json.Serialization;

namespace HighlightBar.Windows;

/// <summary>
/// A named bundle of settings the user can apply in one tap.
/// Built-ins ship with the app; customs are user-saved snapshots.
/// </summary>
[Serializable]
public sealed class Profile
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("settings")]
    public AppSettings Settings { get; set; } = new();

    [JsonPropertyName("isBuiltIn")]
    public bool IsBuiltIn { get; set; } = false;

    public Profile() { }

    public Profile(string name, AppSettings settings, bool isBuiltIn)
    {
        Name = name;
        Settings = settings;
        IsBuiltIn = isBuiltIn;
    }

    public override bool Equals(object? obj)
    {
        return obj is Profile profile && Name == profile.Name;
    }

    public override int GetHashCode()
    {
        return Name.GetHashCode();
    }
}

/// <summary>
/// Manages built-in and user-created profiles.
/// Built-in profiles are defined in code; custom profiles are persisted to JSON.
/// </summary>
public sealed class ProfileStore
{
    private const string CustomProfilesKey = "profiles.custom.v1";
    private const string LastAppliedKey = "profiles.lastApplied.v1";
    private readonly string _configDirectory;
    private readonly string _customProfilesPath;

    /// <summary>
    /// Three accessibility-oriented starting profiles.
    /// </summary>
    public static readonly List<Profile> BuiltIns = new()
    {
        new Profile("Dyslexia", new AppSettings
        {
            Mode = HighlightMode.BarOnly,
            BarShape = BarShape.Ruler,
            BarOrientation = BarOrientation.Horizontal,
            ColorName = "Yellow",
            FontReferenceSize = 26,
            BarOpacityPercent = 30
        }, isBuiltIn: true),

        new Profile("ADHD / Focus", new AppSettings
        {
            Mode = HighlightMode.BarAndSpotlight,
            BarShape = BarShape.Ruler,
            BarOrientation = BarOrientation.Horizontal,
            ColorName = "Yellow",
            FontReferenceSize = 24,
            BarOpacityPercent = 35,
            SpotlightColorName = "Gray",
            SpotlightOpacityPercent = 60
        }, isBuiltIn: true),

        new Profile("Low vision", new AppSettings
        {
            Mode = HighlightMode.BarOnly,
            BarShape = BarShape.Ruler,
            BarOrientation = BarOrientation.Horizontal,
            ColorName = "Yellow",
            FontReferenceSize = 48,
            BarOpacityPercent = 55
        }, isBuiltIn: true)
    };

    public ProfileStore()
    {
        _configDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "HighlightBar"
        );

        _customProfilesPath = Path.Combine(_configDirectory, "profiles.json");

        // Ensure directory exists
        Directory.CreateDirectory(_configDirectory);
    }

    /// <summary>
    /// Load custom profiles from storage.
    /// </summary>
    public List<Profile> LoadCustom()
    {
        try
        {
            if (!File.Exists(_customProfilesPath))
            {
                return new();
            }

            var json = File.ReadAllText(_customProfilesPath);
            var profiles = System.Text.Json.JsonSerializer.Deserialize<List<Profile>>(json);
            return profiles ?? new();
        }
        catch
        {
            // Silently fail and return empty list if deserialization fails
            return new();
        }
    }

    /// <summary>
    /// Save custom profiles to storage.
    /// </summary>
    public void SaveCustom(List<Profile> profiles)
    {
        try
        {
            var json = System.Text.Json.JsonSerializer.Serialize(profiles, new System.Text.Json.JsonSerializerOptions
            {
                WriteIndented = true,
                PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
            });

            File.WriteAllText(_customProfilesPath, json);
        }
        catch
        {
            // Silently fail if unable to save
        }
    }

    /// <summary>
    /// Get the name of the last applied profile, if any.
    /// </summary>
    public string? GetLastAppliedName()
    {
        try
        {
            var settingsPath = Path.Combine(_configDirectory, "settings.json");
            if (!File.Exists(settingsPath))
            {
                return null;
            }

            var json = File.ReadAllText(settingsPath);
            using (var doc = System.Text.Json.JsonDocument.Parse(json))
            {
                if (doc.RootElement.TryGetProperty(LastAppliedKey, out var element) &&
                    element.ValueKind == System.Text.Json.JsonValueKind.String)
                {
                    return element.GetString();
                }

                return null;
            }
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Set the name of the last applied profile.
    /// </summary>
    public void SetLastAppliedName(string? name)
    {
        try
        {
            // Store this in a metadata file or in a separate settings section
            var metaPath = Path.Combine(_configDirectory, "profile-meta.json");
            var meta = new Dictionary<string, string>();

            if (File.Exists(metaPath))
            {
                var json = File.ReadAllText(metaPath);
                meta = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new();
            }

            if (name != null)
            {
                meta[LastAppliedKey] = name;
            }
            else
            {
                meta.Remove(LastAppliedKey);
            }

            var newJson = System.Text.Json.JsonSerializer.Serialize(meta, new System.Text.Json.JsonSerializerOptions
            {
                WriteIndented = true,
                PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
            });

            File.WriteAllText(metaPath, newJson);
        }
        catch
        {
            // Silently fail
        }
    }

    /// <summary>
    /// Get all profiles: built-ins followed by custom.
    /// </summary>
    public List<Profile> GetAllProfiles()
    {
        var all = new List<Profile>(BuiltIns);
        all.AddRange(LoadCustom());
        return all;
    }
}
