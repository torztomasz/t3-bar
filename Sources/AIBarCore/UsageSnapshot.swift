import Foundation

/// One provider's usage at a point in time: every rate-limit window it reports.
public struct UsageSnapshot: Equatable, Sendable {
    public let provider: ProviderID
    public let fetchedAt: Date
    /// In the order the provider wants them displayed.
    public let windows: [UsageWindow]

    public init(provider: ProviderID, fetchedAt: Date, windows: [UsageWindow]) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.windows = windows
    }

    /// The window the menu bar badge shows unless the user picks another: the 5-hour one, because it is the limit a
    /// user runs into mid-session. A provider without one, such as a weekly-only plan, shows its first window.
    public var primaryWindow: UsageWindow? {
        windows.first { $0.kind == .fiveHour } ?? windows.first
    }

    /// The badge's window for the user's choice `id`; nil, or an id this snapshot no longer reports, means the
    /// primary window.
    public func window(for id: String?) -> UsageWindow? {
        windows.first { $0.id == id } ?? primaryWindow
    }
}

/// Identifies a usage provider, e.g. `"claude"`. A wrapper rather than a bare `String` so a provider key
/// cannot be passed where a display name is expected, or vice versa.
public struct ProviderID: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}
