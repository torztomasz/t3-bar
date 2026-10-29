import Foundation

/// A source of rate-limit usage, one per AI service. The app polls every provider and renders whatever they return,
/// so adding a service means adding a conformance, not touching the UI.
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    /// Where the provider appears until the user places it.
    var defaultPlacement: ProviderPlacement { get }
    func fetchUsage() async throws -> UsageSnapshot
}

extension UsageProvider {
    public var defaultPlacement: ProviderPlacement { .menuBar }
}
