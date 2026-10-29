import Foundation

/// The subset of `GET /backend-api/wham/usage` the app reads.
///
/// Every field is optional because the endpoint is undocumented: a window missing what the app needs is skipped
/// instead of failing the whole response.
struct ChatGPTUsageResponse: Decodable {
    let rateLimit: RateLimit?

    struct RateLimit: Decodable {
        /// The shorter window, 5 hours on the plans seen so far.
        let primaryWindow: Window?
        /// The longer window, a week on the plans seen so far.
        let secondaryWindow: Window?
    }

    struct Window: Decodable {
        let usedPercent: Double?
        let limitWindowSeconds: Double?
        /// Seconds since 1970.
        let resetAt: Double?
    }

    var windows: [UsageWindow] {
        [rateLimit?.primaryWindow, rateLimit?.secondaryWindow].compactMap { $0?.window }
    }
}

extension ChatGPTUsageResponse.Window {
    /// Nil without a percent: showing 0% would claim usage the server did not report. Nil without a length too,
    /// since the length is all that tells the windows apart.
    var window: UsageWindow? {
        guard let usedPercent, let limitWindowSeconds else { return nil }
        let identity = WindowIdentity(length: limitWindowSeconds)
        return UsageWindow(id: identity.id, kind: identity.kind, title: identity.title, percentUsed: usedPercent,
                           resetsAt: resetAt.map(Date.init(timeIntervalSince1970:)))
    }
}

extension UsageWindow {
    /// This window under the id and title the ChatGPT endpoint gives it, for a reading of the same limits taken
    /// elsewhere (T3 Code), so it continues the endpoint's history and badge choice.
    func namedLikeChatGPTEndpoint() -> UsageWindow {
        // The endpoint names a window by its length alone, which would lose a per-model window's model.
        let length: TimeInterval
        switch kind {
        case .fiveHour: length = RollingWindow.fiveHours
        case .weekly: length = RollingWindow.week
        case .weeklyModel, .other: return self
        }
        let identity = WindowIdentity(length: length)
        return UsageWindow(id: identity.id, kind: identity.kind, title: identity.title, percentUsed: percentUsed,
                           resetsAt: resetsAt)
    }
}

/// How the app names a ChatGPT window. Named after its length rather than its slot in the response, so a window
/// keeps its id and history if a plan reports it in the other slot.
private struct WindowIdentity {
    let id: String
    let kind: UsageWindow.Kind
    let title: String

    init(length: TimeInterval) {
        switch length {
        case RollingWindow.fiveHours:
            (id, kind, title) = ("five_hour", .fiveHour, "5-hour")
        case RollingWindow.week:
            (id, kind, title) = ("weekly", .weekly, "Weekly")
        default:
            // Kept rather than dropped so a window of a length the app does not know yet still shows.
            (id, kind, title) = ("window_\(Int(length))s", .other, Self.title(forLength: length))
        }
    }

    /// `3-hour`, `30-day`: in days once the length is a whole number of them.
    private static func title(forLength length: TimeInterval) -> String {
        let isWholeDays = length >= RollingWindow.day && length.truncatingRemainder(dividingBy: RollingWindow.day) == 0
        return isWholeDays
            ? "\(Int(length / RollingWindow.day))-day"
            : "\(Int((length / RollingWindow.secondsPerHour).rounded()))-hour"
    }
}
