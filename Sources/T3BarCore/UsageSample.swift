import Foundation

/// One observation of a window's usage, kept over time so the drain rate can be estimated from history.
public struct UsageSample: Codable, Equatable, Sendable {
    public let at: Date
    public let percentUsed: Double

    public init(at: Date, percentUsed: Double) {
        self.at = at
        self.percentUsed = percentUsed
    }
}
