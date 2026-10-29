import Foundation

/// Decides whether a rolling usage window (5-hour or weekly) will be used up before it resets, from the usage samples
/// seen so far.
///
/// The window opens on the first request, so usage at its start is 0% by definition. That start
/// (`resetsAt - windowLength`) serves as an implicit `(start, 0%)` anchor, which is why a single observation is
/// already enough to forecast. The pace is the slope of a least-squares line through the anchor and every sample
/// in the current window: fitting all points smooths out poll jitter instead of trusting the last two readings.
/// The forecast extends that pace from the latest sample to the reset. Samples outside the window (before its
/// start, after the reset, or after `now`) are ignored because they describe another window or a clock glitch.
/// A reading already at 100% is a drained window whatever the pace or reset time.
///
/// Early in a window a line is mostly noise: readings move in whole percents and usage comes in bursts, so the 1–3%
/// of a session's first request, minutes in, projects far past 100%. Until the warm-up ends there is no verdict.
/// It ends once a tenth of the window has passed, so it scales from 30 minutes to about 17 hours for a week, or
/// earlier once a tenth of the limit is used: a pace that just drains the window would only get there at the end of
/// the warm-up, so being there sooner is a real warning, not noise.
public struct DrainEstimator: Sendable {
    public let windowLength: TimeInterval

    public init(windowLength: TimeInterval) {
        self.windowLength = windowLength
    }

    public func forecast(samples: [UsageSample], resetsAt: Date?, now: Date) -> DrainForecast {
        guard let resetsAt else { return forecastWithoutReset(samples: samples, now: now) }
        let windowStart = RollingWindow.start(resetsAt: resetsAt, length: windowLength)
        let inWindow = samples.filter { $0.at >= windowStart && $0.at <= min(now, resetsAt) }
        guard let latest = inWindow.latest else { return .unknown }

        let anchor = UsageSample(at: windowStart, percentUsed: 0)
        let rate = leastSquaresRatePerHour(through: [anchor] + inWindow)
        let projected = rate.map { latest.percentUsed + $0 * hours(from: latest.at, to: resetsAt) }

        if latest.isAtLimit {
            return DrainForecast(outlook: .willDrain(at: now), projectedPercentAtReset: projected,
                                 ratePercentPerHour: rate)
        }
        let warmUpEnd = windowStart.addingTimeInterval(windowLength * warmUpFraction)
        if latest.at < warmUpEnd, latest.percentUsed < limitPercent * warmUpFraction {
            return DrainForecast(outlook: .estimating(until: warmUpEnd), projectedPercentAtReset: nil,
                                 ratePercentPerHour: nil)
        }
        guard let rate, let projected else { return .unknown }
        // Also covers an idle or falling pace: with the latest reading below the limit, a rate <= 0 never reaches it.
        guard projected >= limitPercent else {
            return DrainForecast(outlook: .willLast, projectedPercentAtReset: projected, ratePercentPerHour: rate)
        }
        let drainsAt = latest.at.addingTimeInterval(
            (limitPercent - latest.percentUsed) / rate * RollingWindow.secondsPerHour)
        return DrainForecast(outlook: .willDrain(at: max(drainsAt, now)), projectedPercentAtReset: projected,
                             ratePercentPerHour: rate)
    }

    /// Forecasts a window as the provider reported it. A reset time already in the past means the provider has not
    /// caught up with the reset, so the reading describes a window that is over: the outlook is unknown until a
    /// later poll brings the new window.
    public func forecast(for window: UsageWindow, samples: [UsageSample], now: Date) -> DrainForecast {
        guard !window.isPastReset(now: now) else { return .unknown }
        return forecast(samples: samples, resetsAt: window.resetsAt, now: now)
    }

    /// With no reset time there is nothing to project over, but a reading at the limit still means drained.
    private func forecastWithoutReset(samples: [UsageSample], now: Date) -> DrainForecast {
        guard let latest = samples.filter({ $0.at <= now }).latest, latest.isAtLimit else { return .unknown }
        return DrainForecast(outlook: .willDrain(at: now), projectedPercentAtReset: nil, ratePercentPerHour: nil)
    }
}

/// The verdict the badge colour is drawn from.
public enum DrainOutlook: Equatable, Sendable {
    /// Projected usage at reset stays below 100%.
    case willLast
    /// Projected to reach 100% at this time, before the reset; never earlier than the time asked about.
    case willDrain(at: Date)
    /// Too early in the window to tell a burst from a pace; a verdict comes by this time at the latest.
    case estimating(until: Date)
    /// No reset time, or no sample in the current window to project from.
    case unknown
}

/// The outlook plus the numbers behind it, so the UI can explain a verdict (the bar's projected segment, the lockout).
public struct DrainForecast: Equatable, Sendable {
    public let outlook: DrainOutlook
    /// `nil` when there is no rate to project with (see `ratePercentPerHour`) or while estimating.
    public let projectedPercentAtReset: Double?
    /// `nil` without a reset time, without in-window samples, while estimating, or when every sample shares the
    /// window-start instant.
    public let ratePercentPerHour: Double?

    static let unknown = DrainForecast(outlook: .unknown, projectedPercentAtReset: nil, ratePercentPerHour: nil)

    /// How long the user will be without the provider: from the drain until the reset, which ends the lockout.
    /// Never negative, because a drain reported as "now" can fall after a reset time the provider has not updated.
    public func lockout(resetsAt: Date?) -> TimeInterval? {
        guard case .willDrain(let drainsAt) = outlook, let resetsAt else { return nil }
        return max(resetsAt.timeIntervalSince(drainsAt), 0)
    }
}

private let limitPercent: Double = 100
/// Share of the window's time, and of its limit, that ends the warm-up; see `DrainEstimator`.
private let warmUpFraction = 0.1

private extension UsageSample {
    var isAtLimit: Bool { percentUsed >= limitPercent }
}

private extension Array where Element == UsageSample {
    var latest: UsageSample? { self.max { $0.at < $1.at } }
}

/// Slope of percent against hours; `nil` when all samples share one timestamp, so no line is defined.
private func leastSquaresRatePerHour(through samples: [UsageSample]) -> Double? {
    guard let origin = samples.first?.at else { return nil }
    let xs = samples.map { hours(from: origin, to: $0.at) }
    let ys = samples.map(\.percentUsed)
    let meanX = xs.reduce(0, +) / Double(xs.count)
    let meanY = ys.reduce(0, +) / Double(ys.count)
    let covariance = zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
    let variance = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
    return variance > 0 ? covariance / variance : nil
}

private func hours(from start: Date, to end: Date) -> Double {
    end.timeIntervalSince(start) / RollingWindow.secondsPerHour
}
