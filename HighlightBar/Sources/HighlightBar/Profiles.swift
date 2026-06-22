import Foundation

/// A named bundle of settings the user can apply in one tap. Built-ins ship with
/// the app; customs are user-saved snapshots of the current configuration.
struct Profile: Codable, Equatable {
    var name: String
    var settings: Settings
    var isBuiltIn: Bool
}

/// Persists the user's custom profiles and the last-applied profile name. Built-in
/// profiles live in code; only customs are stored.
final class ProfileStore {
    private let defaults: UserDefaults
    private let customKey = "profiles.custom.v1"
    private let lastAppliedKey = "profiles.lastApplied.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Sensible accessibility-oriented starting points. Every value is tunable
    /// after the profile is applied.
    static let builtIns: [Profile] = {
        var dyslexia = Settings()
        dyslexia.mode = .barOnly
        dyslexia.barShape = .ruler
        dyslexia.barOrientation = .horizontal
        dyslexia.colorName = "Yellow"
        dyslexia.fontReferenceSize = 26
        dyslexia.barOpacity = 0.30

        var focus = Settings()
        focus.mode = .barAndSpotlight
        focus.barShape = .ruler
        focus.barOrientation = .horizontal
        focus.colorName = "Yellow"
        focus.fontReferenceSize = 24
        focus.barOpacity = 0.35
        focus.spotlightColorName = "Gray"
        focus.spotlightOpacity = 0.60

        var lowVision = Settings()
        lowVision.mode = .barOnly
        lowVision.barShape = .ruler
        lowVision.barOrientation = .horizontal
        lowVision.colorName = "Yellow"
        lowVision.fontReferenceSize = 48
        lowVision.barOpacity = 0.55

        return [
            Profile(name: "Dyslexia", settings: dyslexia, isBuiltIn: true),
            Profile(name: "ADHD / Focus", settings: focus, isBuiltIn: true),
            Profile(name: "Low vision", settings: lowVision, isBuiltIn: true)
        ]
    }()

    func loadCustom() -> [Profile] {
        guard let data = defaults.data(forKey: customKey),
              let profiles = try? JSONDecoder().decode([Profile].self, from: data) else {
            return []
        }
        return profiles
    }

    func saveCustom(_ profiles: [Profile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: customKey)
    }

    var lastAppliedName: String? {
        get { defaults.string(forKey: lastAppliedKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: lastAppliedKey)
            } else {
                defaults.removeObject(forKey: lastAppliedKey)
            }
        }
    }

    /// Built-ins followed by user-saved customs.
    func allProfiles() -> [Profile] {
        return ProfileStore.builtIns + loadCustom()
    }
}
