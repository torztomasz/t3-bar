/// What the user can change in the Settings window. Launch at login is not here: the system owns that state, and
/// copying it into preferences would let the two disagree.
public struct AppSettings: Equatable, Sendable {
    /// One of `refreshIntervalChoices` once stored; see `supported()`.
    public var refreshInterval: Duration
    /// The window the menu bar badge shows for each provider; a provider without an entry shows its primary window
    /// (see `UsageSnapshot.window(for:)`). Per provider because window ids are each provider's own.
    public var badgeWindowIDs: [ProviderID: String]
    /// Where each provider's usage appears, for the providers the user has placed. One without an entry appears
    /// where it does by default (`UsageProvider.defaultPlacement`), so one added by an update starts out shown.
    public private(set) var providerPlacements: [ProviderID: ProviderPlacement]
    /// Toggles the usage popover from any app. Off by default: every global shortcut is taken from every other app,
    /// so it is the user's to claim.
    public var openPopoverShortcut: GlobalShortcut?

    /// The badge stacks its readings in a menu bar about 22 pt tall, which fits two legibly (see `BadgeLayout`).
    public static let menuBarCapacity = 2

    /// Short enough to follow a busy session, long enough to stay far from the endpoint's rate limits.
    public static let refreshIntervalChoices: [Duration] = [1, 2, 5, 10, 15].map(Duration.minutes)
    public static let defaultRefreshInterval: Duration = .minutes(5)

    public init(refreshInterval: Duration = defaultRefreshInterval, badgeWindowIDs: [ProviderID: String] = [:],
                providerPlacements: [ProviderID: ProviderPlacement] = [:],
                openPopoverShortcut: GlobalShortcut? = nil) {
        self.refreshInterval = refreshInterval
        self.badgeWindowIDs = badgeWindowIDs
        self.providerPlacements = providerPlacements
        self.openPopoverShortcut = openPopoverShortcut
    }

    /// The default is the provider's own: the settings only know a provider by id.
    public func placement(of provider: ProviderID, defaultingTo defaultPlacement: ProviderPlacement)
        -> ProviderPlacement {
        providerPlacements[provider] ?? defaultPlacement
    }

    /// The providers the badge shows: those placed in the menu bar, up to `menuBarCapacity`, earliest in `providers`
    /// first. Settings stops more being placed there, but a provider T3 Code stopped reporting can come back after
    /// two others took its place.
    public func menuBarProviders(among providers: [(id: ProviderID, defaultPlacement: ProviderPlacement)])
        -> [ProviderID] {
        Array(providers.filter { placement(of: $0.id, defaultingTo: $0.defaultPlacement) == .menuBar }.map(\.id)
            .prefix(Self.menuBarCapacity))
    }

    /// Stores every provider the badge leaves out as Popover only, which is how Settings shows it, so making room
    /// in the menu bar does not bring one back that the user was told is in the popover.
    public mutating func moveMenuBarOverflowToPopover(
        among providers: [(id: ProviderID, defaultPlacement: ProviderPlacement)]
    ) {
        let shown = menuBarProviders(among: providers)
        for provider in providers
        where placement(of: provider.id, defaultingTo: provider.defaultPlacement) == .menuBar
            && !shown.contains(provider.id) {
            place(provider.id, .popoverOnly)
        }
    }

    /// Kept even when it matches the default, which can differ between providers.
    public mutating func place(_ provider: ProviderID, _ placement: ProviderPlacement) {
        providerPlacements[provider] = placement
    }

    /// Replaces an interval the Settings window does not offer with the default, and drops a shortcut that could
    /// never fire, so a value set in code behaves the same as one read back after a relaunch.
    func supported() -> AppSettings {
        var supported = self
        if !Self.refreshIntervalChoices.contains(refreshInterval) {
            supported.refreshInterval = Self.defaultRefreshInterval
        }
        if openPopoverShortcut?.isUsable == false {
            supported.openPopoverShortcut = nil
        }
        return supported
    }
}

/// Intervals are chosen, stored and shown in whole minutes.
extension Duration {
    public static func minutes(_ minutes: Int) -> Duration {
        .seconds(minutes * 60)
    }

    /// Rounded down.
    public var wholeMinutes: Int {
        Int(components.seconds / 60)
    }
}

/// Where a provider's usage appears. One choice rather than a switch per place, so there is no combination that
/// means nothing, such as hidden from the menu bar while turned off.
public enum ProviderPlacement: String, Equatable, Sendable {
    /// In the menu bar badge and in the popover.
    case menuBar
    case popoverOnly
    /// Nowhere, and not fetched.
    case off

    public var isFetched: Bool {
        self != .off
    }
}
