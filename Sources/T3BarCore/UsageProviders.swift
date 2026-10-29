import Foundation

/// The providers the app shows.
public enum UsageProviders {
    /// Every provider T3 Code has usage for, then every account of the cliproxy hubs connected in it. Called on every
    /// refresh, so a provider set up in T3 Code appears without relaunching the app.
    public static func all(t3Code cache: T3CodeProviderCache = T3CodeProviderCache(), hubs: T3CodeHubs)
        -> [any UsageProvider] {
        let instances: [any UsageProvider] = cache.instancesWithUsage()
            .map { T3CodeUsageProvider(instance: $0, cache: cache) }
        let accounts: [any UsageProvider] = hubs.hubs.flatMap { hub in
            hub.accounts.filter { $0.usage != nil }.map { T3CodeHubAccountProvider(account: $0, in: hub, hubs: hubs) }
        }
        return instances + accounts
    }
}
