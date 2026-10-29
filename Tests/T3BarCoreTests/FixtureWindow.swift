import Foundation
@testable import T3BarCore

/// The 5-hour window the time-based tests are laid out on. Fixed dates, so no test depends on the clock.
enum FixtureWindow {
    static let resetsAt = Date(timeIntervalSince1970: 1_800_000_000)
    static let length = RollingWindow.fiveHours

    /// A point `hours` after the window opened; negative values fall in the previous window.
    static func time(hours: Double) -> Date {
        resetsAt.addingTimeInterval((hours - 5) * 3600)
    }
}

extension UsageWindow {
    /// The 5-hour window as the Claude provider reports it; tests vary only the reading and the reset time.
    static func fiveHour(percent: Double, resetsAt: Date? = nil) -> UsageWindow {
        UsageWindow(id: "session", kind: .fiveHour, title: "5-hour", percentUsed: percent, resetsAt: resetsAt)
    }
}

extension DrainForecast {
    /// A forecast carrying only its verdict, for tests about how the verdict is shown.
    static func verdict(_ outlook: DrainOutlook) -> DrainForecast {
        DrainForecast(outlook: outlook, projectedPercentAtReset: nil, ratePercentPerHour: nil)
    }
}
