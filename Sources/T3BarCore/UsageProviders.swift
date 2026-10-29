import Foundation

/// The providers the app shows.
public enum UsageProviders {
    /// Every provider T3 Code has usage for. Called on every refresh, so a provider set up in T3 Code appears without
    /// relaunching the app.
    public static func all(t3Code cache: T3CodeProviderCache = T3CodeProviderCache()) -> [any UsageProvider] {
        cache.instancesWithUsage().map { T3CodeUsageProvider(instance: $0, cache: cache) }
    }
}
