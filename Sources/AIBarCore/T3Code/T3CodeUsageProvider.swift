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

public enum T3CodeUsageError: Error, LocalizedError {
    /// T3 Code has stopped reporting the instance: it was turned off, signed out, or removed since the last refresh.
    case noReading(String)

    public var errorDescription: String? {
        switch self {
        case .noReading(let name): "T3 Code has no usage for \(name) right now. Open T3 Code to see it."
        }
    }
}
