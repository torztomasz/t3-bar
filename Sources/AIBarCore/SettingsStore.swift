import Foundation
import Observation

/// Keeps `AppSettings` in `UserDefaults`, so choices survive relaunches, and announces every change so the app can
/// act on it at once. Observable so the Settings window redraws from the same source of truth it writes to.
///
/// Main-actor bound because its readers (the Settings window, the status item, the poller) all live there.
@MainActor @Observable
public final class SettingsStore {
    /// Always what a fresh store on the same defaults would read, so the app never runs on a value a relaunch would
    /// discard.
    public private(set) var settings: AppSettings
    /// For AppKit consumers that cannot observe; called after every `update`.
    @ObservationIgnored public var onChange: (AppSettings) -> Void = { _ in }

    @ObservationIgnored private let defaults: UserDefaults

    /// The persisted form is primitive (whole minutes, plain strings, a key code with named modifiers) so it stays
    /// readable with `defaults read`.
    enum Key {
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let badgeWindowIDs = "badgeWindowIDs"
        /// From when Claude was the only provider; read as Claude's choice until the first write replaces it.
        static let claudeOnlyBadgeWindowID = "badgeWindowID"
        static let providerPlacements = "providerPlacements"
        static let openPopoverShortcut = "openPopoverShortcut"
        static let shortcutKeyCode = "keyCode"
        static let shortcutModifiers = "modifiers"
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = Self.read(from: defaults)
    }

    public func update(_ mutate: (inout AppSettings) -> Void) {
        var changed = settings
        mutate(&changed)
        settings = changed.supported()
        Self.write(settings, to: defaults)
        onChange(settings)
    }

    /// A stored value this version does not offer, e.g. hand-edited or from a future version, reads as the default
    /// rather than failing. Stored minutes are matched against the choices, never converted, so no value can overflow.
    private static func read(from defaults: UserDefaults) -> AppSettings {
        let storedMinutes = defaults.object(forKey: Key.refreshIntervalMinutes) as? Int
        return AppSettings(
            refreshInterval: AppSettings.refreshIntervalChoices.first { $0.wholeMinutes == storedMinutes }
                ?? AppSettings.defaultRefreshInterval,
            badgeWindowIDs: readBadgeWindowIDs(from: defaults),
            providerPlacements: readProviderPlacements(from: defaults),
            openPopoverShortcut: readShortcut(defaults.object(forKey: Key.openPopoverShortcut))
        ).supported()
    }

    /// A placement this version does not know is skipped, which leaves its provider where it is by default.
    private static func readProviderPlacements(from defaults: UserDefaults) -> [ProviderID: ProviderPlacement] {
        let stored = defaults.object(forKey: Key.providerPlacements) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { provider, placement in
            ProviderPlacement(rawValue: placement).map { (ProviderID(provider), $0) }
        })
    }

    private static func readBadgeWindowIDs(from defaults: UserDefaults) -> [ProviderID: String] {
        if let stored = defaults.object(forKey: Key.badgeWindowIDs) as? [String: String] {
            return Dictionary(uniqueKeysWithValues: stored.map { (ProviderID($0.key), $0.value) })
        }
        guard let claudeWindowID = defaults.object(forKey: Key.claudeOnlyBadgeWindowID) as? String else { return [:] }
        return [ClaudeUsageProvider.providerID: claudeWindowID]
    }

    private static func readShortcut(_ stored: Any?) -> GlobalShortcut? {
        guard let stored = stored as? [String: Any],
              let keyCode = (stored[Key.shortcutKeyCode] as? Int).flatMap(UInt16.init(exactly:)),
              let modifierNames = stored[Key.shortcutModifiers] as? [String],
              let modifiers = GlobalShortcut.Modifiers(storedNames: modifierNames)
        else { return nil }
        return GlobalShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private static func write(_ settings: AppSettings, to defaults: UserDefaults) {
        defaults.set(settings.refreshInterval.wholeMinutes, forKey: Key.refreshIntervalMinutes)
        defaults.set(Dictionary(uniqueKeysWithValues: settings.badgeWindowIDs.map { ($0.key.rawValue, $0.value) }),
                     forKey: Key.badgeWindowIDs)
        defaults.removeObject(forKey: Key.claudeOnlyBadgeWindowID)
        defaults.set(
            Dictionary(uniqueKeysWithValues: settings.providerPlacements.map { ($0.key.rawValue, $0.value.rawValue) }),
            forKey: Key.providerPlacements)
        defaults.set(settings.openPopoverShortcut.map { shortcut -> [String: Any] in
            [Key.shortcutKeyCode: Int(shortcut.keyCode), Key.shortcutModifiers: shortcut.modifiers.storedNames]
        }, forKey: Key.openPopoverShortcut)
    }
}
