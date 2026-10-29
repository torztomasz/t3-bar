import Foundation

/// Where the light running around the menu bar pill is, as a function of time, so a display link can draw it frame
/// by frame.
///
/// Positions count laps around the pill's outline from where the light set off. It runs at a constant pace, because
/// it stands for work in progress. When the refresh ends it never vanishes mid-lap, which would read as cut off: the
/// head runs on to the end of its lap and stops at the starting point, and the tail keeps running until it meets the
/// head, so the light drains away where it began. Even a refresh shorter than a lap shows one whole lap.
public struct RefreshTracer: Equatable, Sendable {
    private var motion = Motion.resting

    /// Brisk, so the pill looks busy for as long as the fetch takes, however short.
    static let secondsPerLap: TimeInterval = 0.9
    /// Share of the outline the light covers: long enough to read as a streak at 24 pt, short enough to read as moving.
    static let length = 0.28

    private enum Motion: Equatable, Sendable {
        case resting
        case running(Anchor)
        case finishing(Anchor, endOfLap: Double)
    }

    /// Where the light was at an instant, from which it runs on.
    private struct Anchor: Equatable, Sendable {
        var since: Date
        var head: Double
        var tail: Double

        func travelled(at now: Date) -> Double {
            head + max(now.timeIntervalSince(since), 0) / RefreshTracer.secondsPerLap
        }
    }

    /// The lit stretch of the outline, in laps; the head leads.
    public struct Segment: Equatable, Sendable {
        public var tail: Double
        public var head: Double

        /// `strokeStart` and `strokeEnd` on a path that goes round the outline twice. Twice so that a light
        /// straddling the starting point is still one continuous stroke.
        public var strokeOnDoubledOutline: ClosedRange<Double> {
            let lapOfTail = tail.rounded(.down)
            return (tail - lapOfTail) / 2...(head - lapOfTail) / 2
        }
    }

    public init() {}

    /// Does nothing while already running, so it can follow a refreshing flag that is set again unchanged. Starting
    /// while the light drains away carries on from where it is: the head sets off again and the tail waits for it to
    /// get a full length ahead.
    public mutating func start(at now: Date) {
        switch motion {
        case .running:
            return
        case .resting, .finishing:
            let segment = segment(at: now) ?? Segment(tail: 0, head: 0)
            motion = .running(Anchor(since: now, head: segment.head, tail: segment.tail))
        }
    }

    /// Does nothing unless running.
    public mutating func stop(at now: Date) {
        guard case .running(let anchor) = motion, let segment = segment(at: now) else { return }
        // The head's lap, but never less than the tail's: a light that has only just set off still goes all the way
        // round.
        let endOfLap = max(segment.head.rounded(.up), segment.tail.rounded(.down) + 1)
        motion = .finishing(anchor, endOfLap: endOfLap)
    }

    /// Nil while nothing is lit.
    public func segment(at now: Date) -> Segment? {
        switch motion {
        case .resting:
            return nil
        case .running(let anchor):
            let travelled = anchor.travelled(at: now)
            return Segment(tail: max(anchor.tail, travelled - Self.length), head: travelled)
        case .finishing(let anchor, let endOfLap):
            // Ends by the clock, not by comparing positions, so it agrees exactly with `goesOutAt`.
            guard let goesOutAt, now < goesOutAt else { return nil }
            let travelled = anchor.travelled(at: now)
            let tail = max(anchor.tail, travelled - Self.length)
            return Segment(tail: min(tail, endOfLap), head: min(travelled, endOfLap))
        }
    }

    /// False once the light has drained away, so the display link drawing it can stop.
    public func isMoving(at now: Date) -> Bool {
        segment(at: now) != nil
    }

    /// When the draining light goes out; nil unless it is draining. A display link stops firing while its display
    /// sleeps, so the light needs a clock to go out by, or it would hang mid-lap until the next refresh.
    public var goesOutAt: Date? {
        guard case .finishing(let anchor, let endOfLap) = motion else { return nil }
        // `stop` puts the end of the lap ahead of the tail, so the tail's own run is what reaches it.
        let lapsUntilTailReachesEnd = endOfLap + Self.length - anchor.head
        return anchor.since.addingTimeInterval(lapsUntilTailReachesEnd * Self.secondsPerLap)
    }
}
