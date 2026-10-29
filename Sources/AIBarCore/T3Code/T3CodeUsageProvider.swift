import Foundation

/// A provider AI Bar can only see through T3 Code, such as Antigravity or a second Codex account: its usage is
/// whatever T3 Code last recorded, dated by when T3 Code took it.
///
/// Left to the popover until the user moves it, because the menu bar has room for two stacked readings and Claude
/// and ChatGPT already claim them.
public struct T3CodeUsageProvider: UsageProvider {
    public let id: ProviderID
    public let displayName: String
    public let defaultPlacement = ProviderPlacement.popoverOnly
    private let instanceID: String
    private let cache: T3CodeProviderCache

    public init(instance: T3CodeProviderInstance, cache: T3CodeProviderCache) {
        id = Self.providerID(forInstance: instance.id)
        displayName = instance.displayName
        instanceID = instance.id
        self.cache = cache
    }

    /// Prefixed so an instance id can never collide with a provider AI Bar reads itself.
    public static func providerID(forInstance instanceID: String) -> ProviderID {
        ProviderID("t3code:\(instanceID)")
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        guard let usage = cache.usage(of: instanceID) else { throw T3CodeUsageError.noReading(displayName) }
        return UsageSnapshot(provider: id, fetchedAt: usage.checkedAt, windows: usage.windows)
    }
}

/// Claude or ChatGPT read from T3 Code while it has a recent reading, and from the provider's own endpoint
/// otherwise. Taking T3 Code's reading saves a second client polling the same rate-limited endpoint with the same
/// token; asking the endpoint keeps AI Bar working when T3 Code is closed, paused or not installed.
public struct T3CodeFirstUsageProvider: UsageProvider {
    public var id: ProviderID { direct.id }
    public var displayName: String { direct.displayName }
    private let instanceID: String
    private let cache: T3CodeProviderCache
    private let direct: any UsageProvider
    /// Gives T3 Code's windows the ids and titles `direct` uses, so a window keeps one history and one badge choice
    /// whichever source read it.
    private let naming: @Sendable (UsageWindow) -> UsageWindow

    /// T3 Code re-reads usage every 5 minutes by default; older than that plus a minute's slack means it has paused
    /// (the Mac is locked or on low power) or quit.
    static let freshness: TimeInterval = 6 * 60

    public init(instanceID: String, cache: T3CodeProviderCache, direct: any UsageProvider,
                naming: @escaping @Sendable (UsageWindow) -> UsageWindow) {
        self.instanceID = instanceID
        self.cache = cache
        self.direct = direct
        self.naming = naming
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        guard let usage = cache.usage(of: instanceID), Date().timeIntervalSince(usage.checkedAt) <= Self.freshness
        else { return try await direct.fetchUsage() }
        return UsageSnapshot(provider: id, fetchedAt: usage.checkedAt, windows: usage.windows.map(naming))
    }
}

public enum T3CodeUsageError: Error, LocalizedError {
    /// T3 Code has stopped reporting the instance: it was turned off, signed out, or removed since the last refresh.
    case noReading(String)

    public var errorDescription: String? {
        switch self {
        case .noReading(let name): "T3 Code has no usage for \(name) right now. Open T3 Code to see it."
        }
    }
}
