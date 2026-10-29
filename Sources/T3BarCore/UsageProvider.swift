import Foundation

/// A source of rate-limit usage, one per AI service. The app polls every provider and renders whatever they return,
/// so adding a service means adding a conformance, not touching the UI.
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    /// Which provider it is underneath, as T3 Code names it (e.g. `claudeAgent`, `codex`); picks its logo, so a
    /// second Codex account gets the same one.
    var driver: String { get }
    /// Where the provider appears until the user places it.
    var defaultPlacement: ProviderPlacement { get }
    /// The providers of one pool share a section in the popover, each limit listing every account's bar; nil gives
    /// the provider a section of its own.
    var pool: UsagePool? { get }
    func fetchUsage() async throws -> UsageSnapshot
}

extension UsageProvider {
    public var defaultPlacement: ProviderPlacement { .menuBar }
    public var pool: UsagePool? { nil }
}

/// Accounts used as one, such as those behind a cliproxy hub.
public struct UsagePool: Hashable, Sendable {
    public let id: String
    public let name: String
}
