import Foundation
import Testing
@testable import AIBarCore

// Method: build snapshots by hand with windows in varied orders and assert on which one the badge would show.
@Suite struct PrimaryWindowSelection {
    @Test func picksTheFiveHourWindowEvenWhenItIsNotFirst() {
        let weekly = window("weekly_all", kind: .weekly)
        let fiveHour = window("session", kind: .fiveHour)
        let snapshot = snapshot(windows: [weekly, fiveHour])

        #expect(snapshot.primaryWindow == fiveHour)
    }

    // E.g. ChatGPT on a weekly-only plan, or Antigravity through T3 Code: still something to show.
    @Test func isTheFirstWindowWhenTheProviderReportsNoFiveHourWindow() {
        let weekly = window("weekly_all", kind: .weekly)
        let snapshot = snapshot(windows: [
            weekly,
            window("weekly_scoped:Fable", kind: .weeklyModel(name: "Fable")),
            window("mystery", kind: .other),
        ])

        #expect(snapshot.primaryWindow == weekly)
    }

    @Test func isNilWithoutWindows() {
        #expect(snapshot(windows: []).primaryWindow == nil)
    }
}

// Method: a snapshot with a 5-hour and a weekly window, asked for ids that are present, absent, or nil, asserting on
// which window the badge would show.
@Suite struct BadgeWindowSelection {
    private let fiveHour = window("session", kind: .fiveHour)
    private let weekly = window("weekly_all", kind: .weekly)

    @Test func picksTheWindowWithTheChosenID() {
        #expect(snapshot(windows: [fiveHour, weekly]).window(for: "weekly_all") == weekly)
    }

    @Test func noChoiceMeansThePrimaryWindow() {
        #expect(snapshot(windows: [weekly, fiveHour]).window(for: nil) == fiveHour)
    }

    // The chosen window can disappear, e.g. a per-model weekly cap the provider stops reporting; the badge must
    // still show something.
    @Test func unknownIDFallsBackToThePrimaryWindow() {
        #expect(snapshot(windows: [weekly, fiveHour]).window(for: "weekly_scoped:Gone") == fiveHour)
    }
}

private func window(_ id: String, kind: UsageWindow.Kind) -> UsageWindow {
    UsageWindow(id: id, kind: kind, title: id, percentUsed: 10, resetsAt: nil)
}

private func snapshot(windows: [UsageWindow]) -> UsageSnapshot {
    UsageSnapshot(provider: ProviderID("test"), fetchedAt: Date(timeIntervalSince1970: 0), windows: windows)
}
