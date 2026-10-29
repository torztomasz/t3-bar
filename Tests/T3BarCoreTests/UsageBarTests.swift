import Foundation
import Testing
@testable import T3BarCore

// Method: each threshold is probed on both sides of its boundary (69.9/70, 89.9/90), since an off-by-one in `<`
// versus `<=` is the likely mistake and only shows at the exact boundary.
@Suite struct UsageLevelThresholds {
    @Test func belowSeventyPercentIsOK() {
        #expect(UsageLevel(percent: 0) == .ok)
        #expect(UsageLevel(percent: 69.9) == .ok)
    }

    @Test func fromSeventyUpToNinetyIsAWarning() {
        #expect(UsageLevel(percent: 70) == .warning)
        #expect(UsageLevel(percent: 89.9) == .warning)
    }

    // Overage above 100% is still critical, not something the thresholds forget about.
    @Test func fromNinetyUpIsCritical() {
        #expect(UsageLevel(percent: 90) == .critical)
        #expect(UsageLevel(percent: 130) == .critical)
    }
}

// Method: build bars straight from a reading and a projection, and assert on the fractions of the bar's width and
// the levels that colour them. Fractions are hand-picked percents divided by 100.
@Suite struct UsageBarGeometry {
    // The fill speaks for now (60%, green); the estimate for the reset (95%, red), so a bar warns ahead of time.
    @Test func fillFollowsTheReadingAndEstimateFollowsTheProjection() {
        let bar = UsageBar(percentUsed: 60, projectedPercentAtReset: 95)

        #expect(bar.fill == UsageBar.Segment(fraction: 0.6, level: .ok))
        #expect(bar.estimate == UsageBar.Segment(fraction: 0.95, level: .critical))
    }

    // A bar cannot extend past its end, but a projected overage is still critical.
    @Test func estimateBeyondTheLimitStopsAtTheEndOfTheBar() {
        let bar = UsageBar(percentUsed: 80, projectedPercentAtReset: 140)

        #expect(bar.fill == UsageBar.Segment(fraction: 0.8, level: .warning))
        #expect(bar.estimate == UsageBar.Segment(fraction: 1, level: .critical))
    }

    @Test func noProjectionMeansNoEstimate() {
        #expect(UsageBar(percentUsed: 40, projectedPercentAtReset: nil).estimate == nil)
    }

    // A flat or falling pace projects nothing beyond the fill, so there is nothing to draw.
    @Test func projectionNotAboveTheReadingMeansNoEstimate() {
        #expect(UsageBar(percentUsed: 40, projectedPercentAtReset: 40).estimate == nil)
        #expect(UsageBar(percentUsed: 40, projectedPercentAtReset: 30).estimate == nil)
    }

    // A provider may report overage: the fill is full, and a higher projection has no room left to show.
    @Test func overageFillsTheBarWithNoRoomForAnEstimate() {
        let bar = UsageBar(percentUsed: 110, projectedPercentAtReset: 150)

        #expect(bar.fill == UsageBar.Segment(fraction: 1, level: .critical))
        #expect(bar.estimate == nil)
    }
}

// Method: lay a 5-hour window out on `FixtureWindow` and build its bar at chosen moments, so the expected fraction is
// the hour offset divided by five.
@Suite struct UsageBarTimeCursor {
    @Test func atTheWindowsOpeningNoTimeHasElapsed() {
        #expect(bar(at: FixtureWindow.time(hours: 0)).elapsedFraction == 0)
    }

    @Test func halfwayThroughTheWindowIsHalfElapsed() {
        #expect(bar(at: FixtureWindow.time(hours: 2.5)).elapsedFraction == 0.5)
    }

    // The provider may not have caught up with the reset yet; the cursor waits at the end instead of leaving the bar.
    @Test func pastTheResetStaysAtTheEnd() {
        #expect(bar(at: FixtureWindow.time(hours: 6)).elapsedFraction == 1)
    }

    @Test func withoutAResetTimeThereIsNoCursor() {
        let window = UsageWindow.fiveHour(percent: 40, resetsAt: nil)

        #expect(UsageBar(window: window, forecast: nil, now: FixtureWindow.time(hours: 1)).elapsedFraction == nil)
    }

    // A window the app does not understand has no known length, so no known start.
    @Test func windowOfUnknownLengthHasNoCursor() {
        let window = UsageWindow(id: "new", kind: .other, title: "New", percentUsed: 40,
                                 resetsAt: FixtureWindow.resetsAt)

        #expect(UsageBar(window: window, forecast: nil, now: FixtureWindow.time(hours: 1)).elapsedFraction == nil)
    }

    // Built from a window and its forecast, the bar still reads fill and estimate the way it always did.
    @Test func fillAndEstimateComeFromTheReadingAndTheForecast() {
        let forecast = DrainForecast(outlook: .willLast, projectedPercentAtReset: 95, ratePercentPerHour: 10)
        let bar = UsageBar(window: .fiveHour(percent: 60, resetsAt: FixtureWindow.resetsAt), forecast: forecast,
                           now: FixtureWindow.time(hours: 1))

        #expect(bar.fill == UsageBar.Segment(fraction: 0.6, level: .ok))
        #expect(bar.estimate == UsageBar.Segment(fraction: 0.95, level: .critical))
    }

    private func bar(at now: Date) -> UsageBar {
        UsageBar(window: .fiveHour(percent: 40, resetsAt: FixtureWindow.resetsAt), forecast: nil, now: now)
    }
}
