import Foundation
import Testing
@testable import AIBarCore

// Method: each test gets a fresh temp directory for the sample files and feeds the forecaster snapshots laid out on
// the fixed 5-hour `FixtureWindow`, the way the app does after each poll. A restart is simulated by opening a second
// forecaster on the same directory. Expected rates are worked out by hand from the anchor rule (0% when the window
// opened) and restated in each test.
@MainActor @Suite final class WindowForecasterBehavior {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // 5-hour: anchor (0h, 0%) and (2.5h, 30%) give 12%/h, projecting 60% at reset.
    // Weekly: 35% at 3.5 days into the week is 10%/day, projecting 70% at reset. Were the weekly window treated as
    // 5 hours long, the reading would fall before its window opened and there would be no forecast at all.
    @Test func forecastsEveryWindowOverItsOwnLength() throws {
        let now = FixtureWindow.time(hours: 2.5)
        let weekly = weeklyWindow(percent: 35, resetsAt: now.addingTimeInterval(3.5 * RollingWindow.day))

        let forecasts = WindowForecaster(directory: directory)
            .forecasts(for: snapshot(at: now, [.fiveHour(percent: 30, resetsAt: FixtureWindow.resetsAt), weekly]))

        #expect(forecasts["session"]?.projectedPercentAtReset == 60)
        #expect(forecasts["session"]?.outlook == .willLast)
        let weeklyProjection = try #require(forecasts["weekly_all"]?.projectedPercentAtReset)
        #expect(abs(weeklyProjection - 70) < 1e-9)
        #expect(forecasts["weekly_all"]?.outlook == .willLast)
    }

    // Without a known length there is no window start to anchor on, so no forecast is offered.
    @Test func windowOfUnknownKindIsNotForecast() {
        let mystery = UsageWindow(id: "mystery", kind: .other, title: "Mystery", percentUsed: 50,
                                  resetsAt: FixtureWindow.resetsAt)

        let forecasts = WindowForecaster(directory: directory)
            .forecasts(for: snapshot(at: FixtureWindow.time(hours: 2.5), [mystery]))

        #expect(forecasts["mystery"] == nil)
    }

    // The 5-hour window reads 1% at 1h, then 59% at 3h after a restart. Fitted with the anchor that is 21%/h (see
    // DrainEstimatorTests). A weekly window sitting at 90% in both polls shares the snapshots; had its samples landed
    // in the 5-hour history, the fit would be pulled far off 21%/h.
    @Test func eachWindowKeepsItsOwnHistoryAcrossRestarts() throws {
        let weekly = weeklyWindow(percent: 90, resetsAt: FixtureWindow.resetsAt.addingTimeInterval(RollingWindow.day))
        _ = WindowForecaster(directory: directory).forecasts(for: snapshot(
            at: FixtureWindow.time(hours: 1), [.fiveHour(percent: 1, resetsAt: FixtureWindow.resetsAt), weekly]))

        let forecasts = WindowForecaster(directory: directory).forecasts(for: snapshot(
            at: FixtureWindow.time(hours: 3), [.fiveHour(percent: 59, resetsAt: FixtureWindow.resetsAt), weekly]))

        let rate = try #require(forecasts["session"]?.ratePercentPerHour)
        #expect(abs(rate - 21) < 1e-9)
    }

    // The file name is the only place the history is found again after a restart, so it must be the same for the
    // same window every time and free of `:` and `·`, which the ids carry. Each character becomes its UTF-8 bytes in
    // %XX form: `:` is 3A, `·` is C2 B7.
    @Test func keepsEachWindowInAFileNamedAfterProviderAndWindow() throws {
        let fable = UsageWindow(id: "weekly_scoped:Fable·2", kind: .weeklyModel(name: "Fable"),
                                title: "Weekly · Fable", percentUsed: 10, resetsAt: FixtureWindow.resetsAt)

        _ = WindowForecaster(directory: directory).forecasts(for: snapshot(
            at: FixtureWindow.time(hours: 1), [.fiveHour(percent: 1, resetsAt: FixtureWindow.resetsAt), fable]))

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(Set(files) == ["samples-claude-session.json", "samples-claude-weekly_scoped%3AFable%C2%B72.json"])
    }

    // Only the location is checked, so the test never writes to the real history.
    @Test func appKeepsHistoryInApplicationSupport() {
        let path = WindowForecaster.inApplicationSupport().directory.path(percentEncoded: false)

        #expect(path.hasSuffix("/Library/Application Support/AI Bar/"))
    }

    private func snapshot(at fetchedAt: Date, _ windows: [UsageWindow]) -> UsageSnapshot {
        UsageSnapshot(provider: ProviderID("claude"), fetchedAt: fetchedAt, windows: windows)
    }

    private func weeklyWindow(percent: Double, resetsAt: Date) -> UsageWindow {
        UsageWindow(id: "weekly_all", kind: .weekly, title: "Weekly", percentUsed: percent, resetsAt: resetsAt)
    }
}
