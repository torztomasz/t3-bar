import Foundation

/// One provider instance T3 Code runs, such as Claude, Codex, Antigravity or a second Codex account: its usage is
/// whatever T3 Code last recorded, dated by when T3 Code took it.
public struct T3CodeUsageProvider: UsageProvider {
    public let id: ProviderID
    public let displayName: String
    public let driver: String
    public let defaultPlacement: ProviderPlacement
    private let cache: T3CodeProviderCache

    /// T3 Code's built-in Claude and Codex start in the menu bar, which has room for two stacked readings; any
    /// other instance starts in the popover.
    public init(instance: T3CodeProviderInstance, cache: T3CodeProviderCache) {
        id = ProviderID(instance.id)
        displayName = instance.displayName
        driver = instance.driver
        defaultPlacement = T3CodeProviderInstance.builtInIDs.contains(instance.id) ? .menuBar : .popoverOnly
        self.cache = cache
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        guard let usage = cache.usage(of: id.rawValue) else { throw T3CodeUsageError.noReading(displayName) }
        return UsageSnapshot(provider: id, fetchedAt: usage.checkedAt, windows: usage.windows)
    }
}

/// One account in a cliproxy hub connected in T3 Code. Starts in the popover: a hub pools several accounts, more
/// than the menu bar has room for.
public struct T3CodeHubAccountProvider: UsageProvider {
    public let id: ProviderID
    public let displayName: String
    public let driver: String
    public let defaultPlacement = ProviderPlacement.popoverOnly
    private let hubID: String
    private let accountID: String
    private let hubs: T3CodeHubs

    /// Named by its email, which is how a pool's accounts are told apart; the hub's own id is the fallback.
    public init(account: T3CodeHubAccount, in hub: T3CodeHub, hubs: T3CodeHubs) {
        id = ProviderID("cliproxy:\(hub.id):\(account.id)")
        displayName = account.email ?? account.id
        driver = account.driver
        hubID = hub.id
        accountID = account.id
        self.hubs = hubs
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let account = hubs.hubs.first { $0.id == hubID }?.accounts.first { $0.id == accountID }
        guard let usage = account?.usage else { throw T3CodeUsageError.noReading(displayName) }
        return UsageSnapshot(provider: id, fetchedAt: usage.checkedAt, windows: usage.windows)
    }
}

/// A hub T3 Code could not read, shown under its label with T3 Code's reason, so a pool that went missing from the
/// popover says why instead of vanishing.
public struct T3CodeUnreadHubProvider: UsageProvider {
    public let id: ProviderID
    public let displayName: String
    public let driver = "cliproxy"
    public let defaultPlacement = ProviderPlacement.popoverOnly
    private let reason: String

    public init(hub: T3CodeHub, reason: String) {
        id = ProviderID("cliproxy:\(hub.id)")
        displayName = hub.label
        self.reason = reason
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        throw T3CodeUsageError.unreadHub(reason)
    }
}

public enum T3CodeUsageError: Error, LocalizedError {
    /// T3 Code has stopped reporting the instance: it was turned off, signed out, or removed since the last refresh.
    case noReading(String)
    /// T3 Code reached for the hub's accounts and failed; the reason is T3 Code's.
    case unreadHub(String)

    public var errorDescription: String? {
        switch self {
        case .noReading(let name): "T3 Code has no usage for \(name) right now. Open T3 Code to see it."
        case .unreadHub(let reason): "T3 Code can't read this hub's accounts: \(reason)"
        }
    }
}
