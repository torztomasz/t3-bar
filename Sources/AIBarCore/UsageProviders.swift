import Foundation

/// The providers the app shows.
public enum UsageProviders {
    /// Every provider T3 Code has usage for, its built-in Claude and Codex first. Called on every refresh, so a
    /// provider set up in T3 Code appears without relaunching the app.
    public static func all(t3Code cache: T3CodeProviderCache = T3CodeProviderCache()) -> [any UsageProvider] {
        func rank(_ instance: T3CodeProviderInstance) -> Int {
            T3CodeProviderInstance.builtInIDs.firstIndex(of: instance.id) ?? T3CodeProviderInstance.builtInIDs.count
        }
        // Stable, so the instances after the built-in ones keep the cache's order by id.
        return cache.instancesWithUsage().enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map { T3CodeUsageProvider(instance: $0.element, cache: cache) }
    }
}
