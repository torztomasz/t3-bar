import Foundation
import Testing
@testable import T3BarCore

// Method (all suites in this file): every time is an offset from one fixed `now` (no `Date()`), written out in
// hours, minutes and seconds so the expected wording can be read straight off the offset, and each test asserts on
// the exact string the user would read.
@Suite struct ResetCountdownText {
    // Seconds are dropped, not rounded up, so the countdown never claims more time than is left.
    @Test func showsHoursAndMinutesLeft() {
        #expect(UsageText.resetsIn(after(hours: 2, minutes: 13, seconds: 50), now: now) == "resets in 2h 13m")
    }

    @Test func omitsHoursUnderAnHour() {
        #expect(UsageText.resetsIn(after(minutes: 45), now: now) == "resets in 45m")
    }

    @Test func showsDaysForWeeklyWindows() {
        #expect(UsageText.resetsIn(after(hours: 4 * 24 + 3, minutes: 12), now: now) == "resets in 4d 3h 12m")
    }

    @Test func underAMinuteIsNotShownAsZero() {
        #expect(UsageText.resetsIn(after(seconds: 20), now: now) == "resets in <1m")
    }

    // The provider has not caught up with the reset yet; a negative countdown would be nonsense.
    @Test func resetTimeInThePastReadsAsNow() {
        #expect(UsageText.resetsIn(after(minutes: -3), now: now) == "resets now")
    }

    @Test func unknownResetTimeIsADash() {
        #expect(UsageText.resetsIn(nil, now: now) == "—")
    }
}

@Suite struct LastUpdatedText {
    @Test func showsWholeMinutesSinceTheRefresh() {
        #expect(UsageText.updated(after(minutes: -3, seconds: -40), now: now) == "Updated 3 min ago")
    }

    // Right after a refresh "0 min ago" would read like a glitch.
    @Test func underAMinuteReadsAsJustNow() {
        #expect(UsageText.updated(after(seconds: -20), now: now) == "Updated just now")
    }

    // After sleep or repeated failures the age can run to hours; "95 min" is harder to read than "1h 35m".
    @Test func anHourOrMoreUsesHoursAndMinutes() {
        #expect(UsageText.updated(after(hours: -1, minutes: -35), now: now) == "Updated 1h 35m ago")
    }

    @Test func neverRefreshedSaysSo() {
        #expect(UsageText.updated(nil, now: now) == "Not updated yet")
    }
}

@Suite struct LockoutLineText {
    // Draining in 1h with the reset at 2h20m leaves 1h20m without the provider.
    @Test func drainBeforeResetSaysHowLongTheLockoutLasts() {
        let forecast = DrainForecast.verdict(.willDrain(at: after(hours: 1)))

        #expect(UsageText.lockout(forecast, resetsAt: after(hours: 2, minutes: 20), now: now)
            == "Locked out for ~1h 20m")
    }

    // A weekly lockout is a projection days out; to the minute would claim precision it does not have. 2d 18h 40m
    // rounds to the nearest hour.
    @Test func lockoutOfADayOrMoreIsInDaysAndHours() {
        let forecast = DrainForecast.verdict(.willDrain(at: now))

        #expect(UsageText.lockout(forecast, resetsAt: after(hours: 2 * 24 + 18, minutes: 40), now: now)
            == "Locked out for ~2d 19h")
    }

    // 2d 0h 20m rounds to a whole number of days; "~2d 0h" would spell out a zero.
    @Test func lockoutOfWholeDaysLeavesOutZeroHours() {
        let forecast = DrainForecast.verdict(.willDrain(at: now))

        #expect(UsageText.lockout(forecast, resetsAt: after(hours: 2 * 24, minutes: 20), now: now)
            == "Locked out for ~2d")
    }

    // 23h 50m is under a day, so it keeps its minutes rather than rounding up into "~1d 0h".
    @Test func lockoutUnderADayKeepsItsMinutes() {
        let forecast = DrainForecast.verdict(.willDrain(at: now))

        #expect(UsageText.lockout(forecast, resetsAt: after(hours: 23, minutes: 50), now: now)
            == "Locked out for ~23h 50m")
    }

    // A window at its limit drains even when the provider gives no reset time; nothing says how long it lasts.
    @Test func drainWithoutAResetTimeIsALockoutOfUnknownLength() {
        #expect(UsageText.lockout(.verdict(.willDrain(at: now)), resetsAt: nil, now: now) == "Locked out")
    }

    @Test func windowThatLastsSaysSo() {
        #expect(UsageText.lockout(.verdict(.willLast), resetsAt: after(hours: 2), now: now) == "Lasts to reset")
    }

    // The warm-up ends at the latest by `until`; usage racing ahead can end it sooner, so this is an upper bound.
    @Test func warmUpSaysWhenTheEstimateArrives() {
        let forecast = DrainForecast.verdict(.estimating(until: after(minutes: 18, seconds: 30)))

        #expect(UsageText.lockout(forecast, resetsAt: after(hours: 4), now: now) == "Estimate in 18m")
    }

    @Test func unknownOrMissingForecastHasNoEstimateYet() {
        #expect(UsageText.lockout(.verdict(.unknown), resetsAt: after(hours: 2), now: now) == "No estimate yet")
        #expect(UsageText.lockout(nil, resetsAt: after(hours: 2), now: now) == "No estimate yet")
    }
}

@Suite struct StatusItemTooltip {
    // Draining 53 minutes from now with the reset at 2h13m leaves 1h20m locked out.
    @Test func spellsOutPercentResetAndLockout() {
        let window = UsageWindow.fiveHour(percent: 42, resetsAt: after(hours: 2, minutes: 13))

        #expect(tooltip(window, .verdict(.willDrain(at: after(minutes: 53))))
            == "Claude 5-hour: 42% · resets in 2h 13m · locked out for ~1h 20m")
    }

    // Lasting to the reset is the normal case; the tooltip only grows when there is something to warn about.
    @Test func windowThatLastsAddsNothing() {
        let window = UsageWindow.fiveHour(percent: 42, resetsAt: after(hours: 2, minutes: 13))

        #expect(tooltip(window, .verdict(.willLast)) == "Claude 5-hour: 42% · resets in 2h 13m")
    }

    // At the limit with no reset time the badge is red, so the tooltip still says why, without a length.
    @Test func drainWithoutAResetTimeSaysLockedOut() {
        #expect(tooltip(.fiveHour(percent: 100), .verdict(.willDrain(at: now))) == "Claude 5-hour: 100% · locked out")
    }

    // Parts the data cannot back are left out instead of shown as placeholders.
    @Test func omitsResetAndProjectionWhenUnknown() {
        #expect(tooltip(.fiveHour(percent: 42, resetsAt: nil), nil) == "Claude 5-hour: 42%")
    }

    @Test func explainsAFailureWhenThereIsNoData() {
        let text = UsageText.tooltip(providerName: "Claude", window: nil, forecast: nil,
                                     errorDescription: "Sign in to Claude Code to see usage.", now: now)

        #expect(text == "Claude: Sign in to Claude Code to see usage.")
    }

    // The badge keeps the last reading after a failed refresh, so the tooltip is where the user learns it is stale.
    @Test func flagsAFailedRefreshAfterTheLastReading() {
        let text = UsageText.tooltip(providerName: "Claude", window: .fiveHour(percent: 100),
                                     forecast: .verdict(.willDrain(at: now)), errorDescription: "Can't reach Claude.",
                                     now: now)

        #expect(text == "Claude 5-hour: 100% · locked out · last refresh failed: Can't reach Claude.")
    }

    @Test func saysWhenThereIsNoDataYet() {
        #expect(tooltip(nil, nil) == "Claude: no usage data yet")
    }

    private func tooltip(_ window: UsageWindow?, _ forecast: DrainForecast?) -> String {
        UsageText.tooltip(providerName: "Claude", window: window, forecast: forecast, errorDescription: nil,
                          now: now)
    }
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func after(hours: Double = 0, minutes: Double = 0, seconds: Double = 0) -> Date {
    now.addingTimeInterval(hours * 3600 + minutes * 60 + seconds)
}
