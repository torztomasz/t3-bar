import Foundation

/// What a window's bar draws: a solid fill for the reading now, behind it a translucent estimate reaching to the
/// projected reading at reset, and on top a cursor at how much of the window's time has passed. A fill ahead of the
/// cursor is usage outpacing time, so the bar shows where usage is heading and not only where it is.
///
/// Every position is measured from the bar's leading edge as a fraction of its width (0...1). The estimate is drawn
/// from the leading edge too, under the fill, so only its part past the fill shows; starting it at the fill's end
/// instead would leave a notch where the fill's rounded end meets it.
public struct UsageBar: Equatable, Sendable {
    public let fill: Segment
    /// `nil` without a projection, or when the projection does not reach past the fill.
    public let estimate: Segment?
    /// `nil` when the window's start is unknown: no reset time, or a window of unknown length.
    public let elapsedFraction: Double?

    public struct Segment: Equatable, Sendable {
        public let fraction: Double
        /// From the unclamped percent, so an overage past the end of the bar still reads as critical.
        public let level: UsageLevel

        public init(fraction: Double, level: UsageLevel) {
            self.fraction = fraction
            self.level = level
        }

        init(percent: Double) {
            self.init(fraction: percent.clamped(to: 0...100) / 100, level: UsageLevel(percent: percent))
        }
    }

    public init(window: UsageWindow, forecast: DrainForecast?, now: Date) {
        self.init(percentUsed: window.percentUsed, projectedPercentAtReset: forecast?.projectedPercentAtReset,
                  elapsedFraction: Self.elapsedFraction(of: window, now: now))
    }

    init(percentUsed: Double, projectedPercentAtReset: Double?, elapsedFraction: Double? = nil) {
        let fill = Segment(percent: percentUsed)
        let estimate = projectedPercentAtReset.map(Segment.init(percent:))
        self.fill = fill
        self.estimate = estimate.flatMap { $0.fraction > fill.fraction ? $0 : nil }
        self.elapsedFraction = elapsedFraction
    }

    /// Clamped, because a reading can outlive its window until the provider reports the reset, and the cursor
    /// should wait at the end of the bar rather than leave it.
    private static func elapsedFraction(of window: UsageWindow, now: Date) -> Double? {
        guard let resetsAt = window.resetsAt, let length = window.kind.length else { return nil }
        let start = RollingWindow.start(resetsAt: resetsAt, length: length)
        return (now.timeIntervalSince(start) / length).clamped(to: 0...1)
    }
}

/// How close a reading is to its limit, which decides a bar's colour. Thresholds rather than a gradient so the
/// colour changes at points a user can learn: 70% is time to pace yourself, 90% is about to run out.
public enum UsageLevel: Equatable, Sendable {
    case ok
    case warning
    case critical

    public init(percent: Double) {
        switch percent {
        case ..<70: self = .ok
        case ..<90: self = .warning
        default: self = .critical
        }
    }
}
