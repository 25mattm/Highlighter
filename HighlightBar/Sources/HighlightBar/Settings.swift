import Foundation

/// The top-level display mode. Drives what the bar/overlays show; persisted as
/// its raw string.
enum HighlightMode: String, Codable, CaseIterable {
    case off
    case barOnly
    case barAndSpotlight
    case screenTint

    var menuTitle: String {
        switch self {
        case .off: return "Off"
        case .barOnly: return "Bar only"
        case .barAndSpotlight: return "Bar + spotlight"
        case .screenTint: return "Screen tint"
        }
    }

    var showsBar: Bool {
        return self == .barOnly || self == .barAndSpotlight
    }
}

/// The single source of truth for everything the user can configure. Persisted
/// as JSON under one `UserDefaults` key so it can grow over the project's phases
/// without scattering keys.
///
/// Decoding is intentionally tolerant: `init(from:)` uses `decodeIfPresent` with
/// a default for every field, so adding a new setting in a later phase never
/// invalidates a user's previously-saved JSON.
struct Settings: Codable, Equatable {
    var fontReferenceSize: Double = 22
    var barOpacity: Double = 0.35
    var colorName: String = "Yellow"

    // Lock mode (Phase 2). When locked the bar freezes at the anchor — the
    // center point of its frame at the moment it was locked — instead of
    // following the cursor. Stored in global screen points.
    var isLocked: Bool = false
    var lockedAnchorX: Double?
    var lockedAnchorY: Double?

    // Overlay modes (Phase 3). The mode plus per-mode color/opacity for the
    // spotlight dim and the screen tint.
    var mode: HighlightMode = .barOnly
    var spotlightColorName: String = "Gray"
    var spotlightOpacity: Double = 0.5
    var tintColorName: String = "Yellow"
    var tintOpacity: Double = 0.2

    init() {}

    private enum CodingKeys: String, CodingKey {
        case fontReferenceSize
        case barOpacity
        case colorName
        case isLocked
        case lockedAnchorX
        case lockedAnchorY
        case mode
        case spotlightColorName
        case spotlightOpacity
        case tintColorName
        case tintOpacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = Settings()
        settings.fontReferenceSize = try container.decodeIfPresent(Double.self, forKey: .fontReferenceSize) ?? settings.fontReferenceSize
        settings.barOpacity = try container.decodeIfPresent(Double.self, forKey: .barOpacity) ?? settings.barOpacity
        settings.colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? settings.colorName
        settings.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? settings.isLocked
        settings.lockedAnchorX = try container.decodeIfPresent(Double.self, forKey: .lockedAnchorX) ?? settings.lockedAnchorX
        settings.lockedAnchorY = try container.decodeIfPresent(Double.self, forKey: .lockedAnchorY) ?? settings.lockedAnchorY
        settings.mode = try container.decodeIfPresent(HighlightMode.self, forKey: .mode) ?? settings.mode
        settings.spotlightColorName = try container.decodeIfPresent(String.self, forKey: .spotlightColorName) ?? settings.spotlightColorName
        settings.spotlightOpacity = try container.decodeIfPresent(Double.self, forKey: .spotlightOpacity) ?? settings.spotlightOpacity
        settings.tintColorName = try container.decodeIfPresent(String.self, forKey: .tintColorName) ?? settings.tintColorName
        settings.tintOpacity = try container.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? settings.tintOpacity
        self = settings
    }
}

/// Loads and saves `Settings` to `UserDefaults`. On first load it migrates the
/// pre-Settings flat keys so existing users keep their configuration.
final class SettingsStore {
    private let defaults: UserDefaults
    private let storageKey = "settings.v1"

    /// Flat keys used before the unified `Settings` model existed.
    private enum LegacyKey {
        static let fontReferenceSize = "fontReferenceSize"
        static let barOpacity = "barOpacity"
        static let colorName = "colorName"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Settings {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            return decoded
        }
        return migratedFromLegacyKeys() ?? Settings()
    }

    func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func migratedFromLegacyKeys() -> Settings? {
        let hasLegacyValues = defaults.object(forKey: LegacyKey.fontReferenceSize) != nil
            || defaults.object(forKey: LegacyKey.barOpacity) != nil
            || defaults.string(forKey: LegacyKey.colorName) != nil
        guard hasLegacyValues else { return nil }

        var settings = Settings()
        if let value = defaults.object(forKey: LegacyKey.fontReferenceSize) as? Double {
            settings.fontReferenceSize = value
        }
        if let value = defaults.object(forKey: LegacyKey.barOpacity) as? Double {
            settings.barOpacity = value
        }
        if let value = defaults.string(forKey: LegacyKey.colorName) {
            settings.colorName = value
        }
        return settings
    }
}
