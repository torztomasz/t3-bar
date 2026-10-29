import Foundation

/// The providers the app shows.
public enum UsageProviders {
    /// Claude and ChatGPT, read through T3 Code when it has them, followed by every other provider T3 Code has usage
    /// for. Called on every refresh, so a provider set up in T3 Code appears without relaunching AI Bar.
    public static func all(t3Code cache: T3CodeProviderCache = T3CodeProviderCache()) -> [any UsageProvider] {
        let readDirectly: Set = [T3CodeProviderInstance.defaultClaudeID, T3CodeProviderInstance.defaultCodexID]
        let onlyInT3Code = cache.instancesWithUsage().filter { !readDirectly.contains($0.id) }
        return [
            T3CodeFirstUsageProvider(instanceID: T3CodeProviderInstance.defaultClaudeID, cache: cache,
                                     direct: ClaudeUsageProvider(), naming: { $0.namedLikeClaudeEndpoint() }),
            T3CodeFirstUsageProvider(instanceID: T3CodeProviderInstance.defaultCodexID, cache: cache,
                                     direct: ChatGPTUsageProvider(), naming: { $0.namedLikeChatGPTEndpoint() }),
        ] + onlyInT3Code.map { T3CodeUsageProvider(instance: $0, cache: cache) }
    }
}
