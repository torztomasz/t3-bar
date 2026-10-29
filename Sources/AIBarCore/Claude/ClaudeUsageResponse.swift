import Foundation

/// The subset of `GET /api/oauth/usage` the app reads.
///
/// Every field is optional because the endpoint is undocumented and sends `null` freely: a window missing what
/// the app needs is skipped instead of failing the whole response.
struct ClaudeUsageResponse: Decodable {
    /// The structured form and the source of truth when it yields any window.
    let limits: [Limit]?
    /// Older flat form, read only when `limits` yields nothing.
    let fiveHour: LegacyWindow?
    let sevenDay: LegacyWindow?

    struct Limit: Decodable {
        let kind: String?
        let percent: Double?
        let resetsAt: String?
        let scope: Scope?
    }

    struct Scope: Decodable {
        let model: Model?
    }

    struct Model: Decodable {
        let displayName: String?
    }

    struct LegacyWindow: Decodable {
        let utilization: Double?
        let resetsAt: String?
    }

    var windows: [UsageWindow] {
        let fromLimits = (limits ?? []).compactMap(\.window)
        return withUniqueIDs(fromLimits.isEmpty ? legacyWindows : inDisplayOrder(fromLimits))
    }

    private var legacyWindows: [UsageWindow] {
        [
            fiveHour.flatMap { WindowIdentity.fiveHour.window(percent: $0.utilization, resetsAt: $0.resetsAt) },
            sevenDay.flatMap { WindowIdentity.weekly.window(percent: $0.utilization, resetsAt: $0.resetsAt) },
        ].compactMap { $0 }
    }
}

extension ClaudeUsageResponse.Limit {
    var window: UsageWindow? {
        guard let kind else { return nil }
        return identity(kind: kind).window(percent: percent, resetsAt: resetsAt)
    }

    private func identity(kind: String) -> WindowIdentity {
        switch (kind, scope?.model?.displayName) {
        case ("session", _): .fiveHour
        case ("weekly_all", _): .weekly
        case ("weekly_scoped", let model?): .weeklyModel(model)
        default: .other(kind)
        }
    }
}

extension UsageWindow {
    /// This window under the id and title the Claude endpoint gives it, for a reading of the same limits taken
    /// elsewhere (T3 Code), so it continues the endpoint's history and badge choice.
    func namedLikeClaudeEndpoint() -> UsageWindow {
        let identity: WindowIdentity
        switch kind {
        case .fiveHour: identity = .fiveHour
        case .weekly: identity = .weekly
        case .weeklyModel(let name): identity = .weeklyModel(name)
        case .other: return self
        }
        return UsageWindow(id: identity.id, kind: identity.kind, title: identity.title, percentUsed: percentUsed,
                           resetsAt: resetsAt)
    }
}

/// How the app names a Claude window. Shared by `limits` and the legacy objects so a window keeps its id
/// whichever shape the server sends.
private struct WindowIdentity {
    let id: String
    let kind: UsageWindow.Kind
    let title: String

    static let fiveHour = WindowIdentity(id: "session", kind: .fiveHour, title: "5-hour")
    static let weekly = WindowIdentity(id: "weekly_all", kind: .weekly, title: "Weekly")

    static func weeklyModel(_ name: String) -> WindowIdentity {
        WindowIdentity(id: "weekly_scoped:\(name)", kind: .weeklyModel(name: name), title: "Weekly · \(name)")
    }

    /// Kept rather than dropped so windows the API adds later still show, titled by their raw kind.
    static func other(_ kind: String) -> WindowIdentity {
        WindowIdentity(id: kind, kind: .other, title: kind)
    }

    /// Nil without a percent: showing 0% would claim usage the server did not report.
    func window(percent: Double?, resetsAt: String?) -> UsageWindow? {
        guard let percent else { return nil }
        return UsageWindow(id: id, kind: kind, title: title, percentUsed: percent,
                           resetsAt: resetsAt.flatMap(parseResetDate))
    }
}

/// Most urgent first: the 5-hour window is the one users hit mid-session. Ties keep the server's order.
private func inDisplayOrder(_ windows: [UsageWindow]) -> [UsageWindow] {
    func rank(_ kind: UsageWindow.Kind) -> Int {
        switch kind {
        case .fiveHour: 0
        case .weekly: 1
        case .weeklyModel: 2
        case .other: 3
        }
    }
    return windows.enumerated()
        .sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }
        .map(\.element)
}

/// `UsageWindow` is `Identifiable` and SwiftUI lists misbehave on repeated ids, which the server can produce
/// (two model-less `weekly_scoped` entries, or two unknown windows of one kind). Repeats get `#2`, `#3`, ….
private func withUniqueIDs(_ windows: [UsageWindow]) -> [UsageWindow] {
    var occurrences: [String: Int] = [:]
    return windows.map { window in
        let occurrence = occurrences[window.id, default: 0] + 1
        occurrences[window.id] = occurrence
        guard occurrence > 1 else { return window }
        return UsageWindow(id: "\(window.id)#\(occurrence)", kind: window.kind, title: window.title,
                           percentUsed: window.percentUsed, resetsAt: window.resetsAt)
    }
}

/// The server sends microsecond fractions (`2026-10-01T23:59:59.686471+00:00`), but a whole-second timestamp is
/// equally valid ISO-8601, so both are accepted rather than dropping the reset time.
func parseResetDate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}
