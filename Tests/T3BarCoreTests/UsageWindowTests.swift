import Foundation
import Testing
@testable import T3BarCore

// Method: each kind's length is compared with the length Claude documents for that limit, written out in seconds.
@Suite struct WindowLengthByKind {
    @Test func sessionWindowLastsFiveHours() {
        #expect(UsageWindow.Kind.fiveHour.length == 18_000)
    }

    @Test func weeklyWindowsLastSevenDays() {
        #expect(UsageWindow.Kind.weekly.length == 604_800)
        #expect(UsageWindow.Kind.weeklyModel(name: "Fable").length == 604_800)
    }

    // Without a length there is no window start, so no anchor to forecast from.
    @Test func unrecognisedWindowHasNoKnownLength() {
        #expect(UsageWindow.Kind.other.length == nil)
    }
}
