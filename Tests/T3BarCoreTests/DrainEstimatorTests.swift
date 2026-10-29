import Foundation
import Testing
@testable import T3BarCore

// Method: every scenario is laid out on the fixed 5-hour `FixtureWindow` (no `Date()`), with samples placed at whole
// or half hours after the window opened, so each expected rate and projection can be worked out by hand in the test.
@Suite struct DrainEstimatorBehavior {
    // Anchor (0h, 0%) and (2.5h, 30%) give 12%/h; 2.5h left adds 30%.
    @Test func singleSampleAtHalfwayOnGentlePaceWillLast() {
        let forecast = forecast([sample(hours: 2.5, 30)], atHour: 2.5)

        #expect(forecast.outlook == .willLast)
        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
    }

    // Anchor (0h, 0%) and (2.5h, 60%) give 24%/h, so 2.5h more adds 60%. The remaining 40% takes 40/24h = 1h40m,
    // so the line crosses 100% at 4h10m, 50 minutes before reset.
    @Test func singleSampleAtHalfwayOnSteepPaceWillDrainBeforeReset() {
        let forecast = forecast([sample(hours: 2.5, 60)], atHour: 2.5)

        #expect(forecast.outlook == .willDrain(at: time(hours: 4 + 10.0 / 60)))
        #expect(forecast.ratePercentPerHour == 24)
        #expect(forecast.projectedPercentAtReset == 120)
    }

    // A burst late in the window: the anchor-to-latest average, 59% over 3h = 19.67%/h, would reach only 98.3% by
    // reset. The least-squares line through (0h,0%) (1h,1%) (3h,59%) has mean (4/3h, 20%), Σdx·dy = 98 and
    // Σdx² = 14/3, so slope 21%/h: the near-idle first hour sits below the line and tilts it steeper. That projects
    // 59 + 21 × 2 = 101% and crosses 100% after another 41/21h, at about 4h57m, just before reset.
    @Test func multipleSamplesAreFittedAsOneLineThroughTheAnchor() throws {
        let forecast = forecast([sample(hours: 1, 1), sample(hours: 3, 59)], atHour: 3)

        let rate = try #require(forecast.ratePercentPerHour)
        let projected = try #require(forecast.projectedPercentAtReset)
        #expect(abs(rate - 21) < 1e-9)
        #expect(abs(projected - 101) < 1e-9)
        #expect(isWithinASecond(forecast.outlook, of: time(hours: 3 + 41.0 / 21)))
    }

    // Same line as the steep single sample (crosses 100% at 4h10m), but the forecast is asked for at 4h30m, e.g.
    // after polls failed. A drain time in the past would be meaningless to show, so it is reported as now.
    @Test func drainTimeAlreadyPassedIsReportedAsNow() {
        let forecast = forecast([sample(hours: 2.5, 60)], atHour: 4.5)

        #expect(forecast.outlook == .willDrain(at: time(hours: 4.5)))
    }

    // The 90% sample an hour before this window opened belongs to the previous window; if it counted, the line
    // would slope downwards. Ignoring it leaves the gentle single-sample case: 12%/h, 60% at reset.
    @Test func samplesFromThePreviousWindowAreIgnored() {
        let forecast = forecast([sample(hours: -1, 90), sample(hours: 2.5, 30)], atHour: 2.5)

        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
        #expect(forecast.outlook == .willLast)
    }

    // A sample stamped after `now` (e.g. the clock moved back) cannot be trusted, so only the 30% one counts.
    @Test func samplesAfterNowAreIgnored() {
        let forecast = forecast([sample(hours: 2.5, 30), sample(hours: 3, 90)], atHour: 2.5)

        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
    }

    // A sample after the reset belongs to the next window (`resetsAt` is stale), so only the 30% one counts.
    @Test func samplesAfterTheResetAreIgnored() {
        let forecast = forecast([sample(hours: 2.5, 30), sample(hours: 5.5, 5)], atHour: 5.5)

        #expect(forecast.ratePercentPerHour == 12)
        #expect(forecast.projectedPercentAtReset == 60)
    }

    // Nothing used yet: every point, anchor included, sits at 0%, so the line is flat.
    @Test func idlePaceWillLast() {
        let forecast = forecast([sample(hours: 1, 0), sample(hours: 3, 0)], atHour: 3)

        #expect(forecast.ratePercentPerHour == 0)
        #expect(forecast.outlook == .willLast)
    }

    // Without a reset time there is no window start, so no anchor and no way to tell current samples from stale.
    @Test func unknownResetTimeGivesNoForecast() {
        let forecast = forecast([sample(hours: 2.5, 60)], atHour: 2.5, resetsAt: nil)

        #expect(forecast == .unknown)
    }

    @Test func windowAtItsLimitDrainsNow() {
        let forecast = forecast([sample(hours: 4, 100)], atHour: 4.5)

        #expect(forecast.outlook == .willDrain(at: time(hours: 4.5)))
    }

    // The reset time only matters for projecting; a window at its limit is drained already, so the badge must say so.
    @Test func windowAtItsLimitDrainsNowEvenWithoutAResetTime() {
        let forecast = forecast([sample(hours: 4, 100)], atHour: 4.5, resetsAt: nil)

        #expect(forecast.outlook == .willDrain(at: time(hours: 4.5)))
    }

    // The only sample is from the previous window, so the anchor is the sole point and there is no slope.
    @Test func anchorAloneGivesNoForecast() {
        let forecast = forecast([sample(hours: -1, 90)], atHour: 1)

        #expect(forecast == .unknown)
    }

    /// Forecast `hours` into the fixture window, against its reset time unless one is given.
    private func forecast(_ samples: [UsageSample], atHour hours: Double,
                          resetsAt: Date? = FixtureWindow.resetsAt) -> DrainForecast {
        estimator.forecast(samples: samples, resetsAt: resetsAt, now: time(hours: hours))
    }
}

// Method: readings placed minutes into the fixture window (warm-up ends at 30 minutes, 10% of 5 hours, or at 10%
// used) and one on a weekly window, each worked out by hand, checking which side of the warm-up it falls on.
@Suite struct WarmUp {
    // The session that prompted the warm-up: 3% two minutes in is a 90%/h line projecting ~450%, though usage then
    // stayed flat for hours. Too little time has passed to tell a burst from a pace, so no verdict and no projection.
    @Test func burstAtTheStartOfAWindowGivesNoVerdictYet() {
        let forecast = forecast([sample(hours: 2.0 / 60, 3)], atHour: 2.0 / 60)

        #expect(forecast.outlook == .estimating(until: time(hours: 0.5)))
        #expect(forecast.projectedPercentAtReset == nil)
        #expect(forecast.ratePercentPerHour == nil)
    }

    // 30 minutes in, the warm-up is over: 3% over 0.5h is 6%/h, so 4.5h more adds 27%, 30% at reset.
    @Test func warmUpEndsAfterATenthOfTheWindow() {
        let forecast = forecast([sample(hours: 0.5, 3)], atHour: 0.5)

        #expect(forecast.outlook == .willLast)
        #expect(forecast.projectedPercentAtReset == 30)
    }

    // 10% used after 10 minutes is ahead of where a pace that just drains the window (20%/h) would be even at the
    // end of the warm-up, so it is a real warning: 60%/h crosses 100% after another 1h30m, at 1h40m.
    @Test func usageAheadOfADrainingPaceEndsTheWarmUpEarly() throws {
        let forecast = forecast([sample(hours: 10.0 / 60, 10)], atHour: 10.0 / 60)

        let rate = try #require(forecast.ratePercentPerHour)
        #expect(abs(rate - 60) < 1e-9)
        #expect(isWithinASecond(forecast.outlook, of: time(hours: 1 + 40.0 / 60)))
    }

    @Test func usageJustBelowTheEarlyExitKeepsEstimating() {
        let forecast = forecast([sample(hours: 10.0 / 60, 9)], atHour: 10.0 / 60)

        #expect(forecast.outlook == .estimating(until: time(hours: 0.5)))
    }

    // Drained is a fact, not a projection, so it needs no warm-up.
    @Test func windowAtItsLimitDrainsNowDuringTheWarmUp() {
        let forecast = forecast([sample(hours: 5.0 / 60, 100)], atHour: 5.0 / 60)

        #expect(forecast.outlook == .willDrain(at: time(hours: 5.0 / 60)))
    }

    // The warm-up scales with the window: 12 hours into a week is well under its tenth, 16h48m.
    @Test func weeklyWindowWarmsUpForATenthOfAWeek() {
        let weekly = DrainEstimator(windowLength: RollingWindow.week)
        let windowStart = FixtureWindow.resetsAt.addingTimeInterval(-RollingWindow.week)
        let noon = windowStart.addingTimeInterval(12 * 3600)

        let forecast = weekly.forecast(samples: [UsageSample(at: noon, percentUsed: 5)],
                                       resetsAt: FixtureWindow.resetsAt, now: noon)

        #expect(forecast.outlook == .estimating(until: windowStart.addingTimeInterval(16.8 * 3600)))
    }

    private func forecast(_ samples: [UsageSample], atHour hours: Double) -> DrainForecast {
        estimator.forecast(samples: samples, resetsAt: FixtureWindow.resetsAt, now: time(hours: hours))
    }
}

// Method: the same fixture window, but forecast through the window as the provider reported it, the way the app does.
@Suite struct ReportedWindowForecast {
    // Polled 10 minutes after the reported reset: the provider has not caught up, so its reading and reset time
    // describe a window that is over. Even a 100% reading must not paint the badge red.
    @Test func windowPastItsResetTimeHasNoForecast() {
        let window = UsageWindow.fiveHour(percent: 100, resetsAt: FixtureWindow.resetsAt)
        let polledAt = time(hours: 5 + 1.0 / 6)

        let forecast = estimator.forecast(for: window, samples: [sample(hours: 4, 100)], now: polledAt)

        #expect(window.isPastReset(now: polledAt))
        #expect(forecast.outlook == .unknown)
    }

    // A current window forecasts exactly as the estimator does: the gentle single-sample case, 12%/h, 60% at reset.
    @Test func windowBeforeItsResetTimeIsForecastNormally() {
        let window = UsageWindow.fiveHour(percent: 30, resetsAt: FixtureWindow.resetsAt)

        let forecast = estimator.forecast(for: window, samples: [sample(hours: 2.5, 30)], now: time(hours: 2.5))

        #expect(!window.isPastReset(now: time(hours: 2.5)))
        #expect(forecast.outlook == .willLast)
        #expect(forecast.projectedPercentAtReset == 60)
    }
}

// Method: verdicts built by hand on the fixture window, so each lockout is the plain gap between a drain time and
// the reset, readable off the hour offsets.
@Suite struct LockoutDuration {
    // Draining 3h30m into a 5-hour window leaves the user without the provider for the last 1h30m.
    @Test func drainBeforeResetLocksOutUntilTheReset() {
        let forecast = DrainForecast.verdict(.willDrain(at: time(hours: 3.5)))

        #expect(forecast.lockout(resetsAt: FixtureWindow.resetsAt) == TimeInterval(90 * 60))
    }

    // A drain reported as "now" can land after a stale reset time; a negative lockout would be nonsense.
    @Test func drainAfterResetIsNoLongerThanZero() {
        let forecast = DrainForecast.verdict(.willDrain(at: time(hours: 5.5)))

        #expect(forecast.lockout(resetsAt: FixtureWindow.resetsAt) == 0)
    }

    @Test func windowThatLastsOrIsUnknownHasNoLockout() {
        #expect(DrainForecast.verdict(.willLast).lockout(resetsAt: FixtureWindow.resetsAt) == nil)
        #expect(DrainForecast.verdict(.unknown).lockout(resetsAt: FixtureWindow.resetsAt) == nil)
    }

    // Without a reset time nothing says when the lockout ends.
    @Test func unknownResetTimeHasNoLockout() {
        #expect(DrainForecast.verdict(.willDrain(at: time(hours: 3.5))).lockout(resetsAt: nil) == nil)
    }
}

private let estimator = DrainEstimator(windowLength: FixtureWindow.length)

private func time(hours: Double) -> Date {
    FixtureWindow.time(hours: hours)
}

private func sample(hours: Double, _ percentUsed: Double) -> UsageSample {
    UsageSample(at: time(hours: hours), percentUsed: percentUsed)
}

/// Drain times come out of floating-point division, so they are compared to the second, the precision a user sees.
private func isWithinASecond(_ outlook: DrainOutlook, of expected: Date) -> Bool {
    guard case .willDrain(let at) = outlook else { return false }
    return abs(at.timeIntervalSince(expected)) < 1
}
