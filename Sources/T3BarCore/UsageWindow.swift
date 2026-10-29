import Foundation

/// One rate-limit window a provider reports, e.g. the 5-hour session or a weekly per-model cap.
///
/// What a window *means* is carried by an explicit `kind` instead of a naming convention on `id`:
/// `id` is the provider's own opaque key, and the app must not break when a provider renames it.
/// `kind` is what the app reasons about (which window drives the badge, how to order rows).
public struct UsageWindow: Equatable, Sendable, Identifiable {
    /// Stable key from the provider, e.g. `"session"`, `"weekly_all"`, `"weekly_scoped:Fable"`.
    public let id: String
    public let kind: Kind
    /// Human label, e.g. `"5-hour"`, `"Weekly"`, `"Weekly · Fable"`.
    public let title: String
    /// 0...100, but may exceed 100 if the provider reports overage.
    public let percentUsed: Double
    public let resetsAt: Date?

    public enum Kind: Equatable, Sendable {
        case fiveHour
        case weekly
        case weeklyModel(name: String)
        /// A window the app does not understand yet; kept so data a provider adds later is still shown.
        case other

        /// How long a window of this kind runs from opening to reset; `nil` for a window the app does not
        /// understand, which therefore cannot be forecast.
        public var length: TimeInterval? {
            switch self {
            case .fiveHour: RollingWindow.fiveHours
            case .weekly, .weeklyModel: RollingWindow.week
            case .other: nil
            }
        }
    }

    public init(id: String, kind: Kind, title: String, percentUsed: Double, resetsAt: Date?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
    }

    /// True once the reported reset time has come, i.e. the reading belongs to a window that is already over.
    public func isPastReset(now: Date) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }
}
