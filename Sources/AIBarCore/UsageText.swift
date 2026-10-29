import Foundation

/// Every string the menu bar item and popover show, as pure functions of the data, so wording and rounding are
/// unit-tested without AppKit and the views only lay text out.
public enum UsageText {
    /// `window` is the one chosen for the badge (see `UsageSnapshot.window(for:)`). A failed fetch with nothing to fall
    /// back on gets a `!` so it is not mistaken for "still loading".
    public static func badge(window: UsageWindow?, hasError: Bool) -> String {
        guard let window else { return hasError ? "--%!" : "--%" }
        return percent(window.percentUsed)
    }

    /// E.g. "Claude 5-hour: 42% · resets in 2h 13m · locked out for ~1h 20m"; parts without data are left out. A window
    /// that lasts is the normal case, so only a lockout is worth the extra words. A failed refresh is appended because
    /// the badge keeps showing the last reading, which would otherwise look current.
    public static func tooltip(providerName: String, window: UsageWindow?, forecast: DrainForecast?,
                               errorDescription: String?, now: Date) -> String {
        guard let window else {
            return "\(providerName): \(errorDescription ?? "no usage data yet")"
        }
        var parts = ["\(providerName) \(window.title): \(percent(window.percentUsed))"]
        if let resetsAt = window.resetsAt {
            parts.append(resetsIn(resetsAt, now: now))
        }
        if case .willDrain = forecast?.outlook {
            parts.append("locked out\(lockoutLength(forecast, resetsAt: window.resetsAt))")
        }
        if let errorDescription {
            parts.append("last refresh failed: \(errorDescription)")
        }
        return parts.joined(separator: " · ")
    }

    /// Shown where usage would be, when the user has turned every provider off.
    public static let noProviders = "Every provider is turned off. Turn one on in Settings."
    public static let noT3Code = "T3 Code isn't reporting any usage. Install T3 Code, or open it and sign in to a provider."

    /// The tooltip of a badge no provider is shown in.
    public static let emptyBadge = "AI Bar: no provider is shown in the menu bar"

    /// Minutes precision, rounded down so the countdown never promises more time than is left.
    public static func resetsIn(_ resetsAt: Date?, now: Date) -> String {
        guard let resetsAt else { return "—" }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return "resets now" }
        return "resets in \(duration(remaining))"
    }

    public static func updated(_ refreshedAt: Date?, now: Date) -> String {
        guard let refreshedAt else { return "Not updated yet" }
        let minutes = Int(now.timeIntervalSince(refreshedAt) / 60)
        switch minutes {
        case ..<1: return "Updated just now"
        case ..<60: return "Updated \(minutes) min ago"
        default: return "Updated \(duration(TimeInterval(minutes * 60))) ago"
        }
    }

    /// Answers "for how long will I be without this provider?" rather than when it drains, which would leave the
    /// reader to do the date arithmetic.
    /// While estimating it says when the verdict arrives, so an uncoloured badge early in a window reads as
    /// "wait", not as broken.
    public static func lockout(_ forecast: DrainForecast?, resetsAt: Date?, now: Date) -> String {
        switch forecast?.outlook {
        case .willDrain:
            return "Locked out\(lockoutLength(forecast, resetsAt: resetsAt))"
        case .willLast:
            return "Lasts to reset"
        case .estimating(let until):
            return "Estimate in \(duration(until.timeIntervalSince(now)))"
        case .unknown, nil:
            return "No estimate yet"
        }
    }

    /// Whole percent, shared by badge, tooltip and popover so they never disagree on rounding.
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// ` for ~1h 20m`, approximate because the drain time is a projection; empty when no reset time says when the
    /// lockout ends.
    private static func lockoutLength(_ forecast: DrainForecast?, resetsAt: Date?) -> String {
        guard let length = forecast?.lockout(resetsAt: resetsAt) else { return "" }
        return " for ~\(length >= RollingWindow.day ? daysAndHours(length) : duration(length))"
    }

    /// `2h 13m`, `4d 3h 12m`: leading zero units are dropped, and anything under a minute reads `<1m` rather than
    /// `0m`, which would suggest the moment has passed.
    static func duration(_ interval: TimeInterval) -> String {
        let parts = DurationParts(minutes: Int(interval / 60))
        if parts.days > 0 { return "\(parts.days)d \(parts.hours)h \(parts.minutes)m" }
        if parts.hours > 0 { return "\(parts.hours)h \(parts.minutes)m" }
        return parts.minutes > 0 ? "\(parts.minutes)m" : "<1m"
    }

    /// `2d 19h`, `2d`: to the nearest hour, for spans of a day or more where minutes would claim precision a
    /// projection days out does not have.
    private static func daysAndHours(_ interval: TimeInterval) -> String {
        let wholeHours = Int((interval / RollingWindow.secondsPerHour).rounded())
        let parts = DurationParts(minutes: wholeHours * 60)
        return parts.hours > 0 ? "\(parts.days)d \(parts.hours)h" : "\(parts.days)d"
    }
}

/// A span split into the units the text shows it in.
private struct DurationParts {
    let days: Int
    let hours: Int
    let minutes: Int

    init(minutes totalMinutes: Int) {
        (days, hours, minutes) = (totalMinutes / 1440, totalMinutes / 60 % 24, totalMinutes % 60)
    }
}
