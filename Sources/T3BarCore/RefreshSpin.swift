import Foundation

/// The angle of the refresh icon, as a function of time, so a display-linked timeline can draw it frame by frame.
///
/// While a refresh runs the icon turns at a constant rate. When it ends, the icon eases out to the next upright
/// position instead of freezing at a tilt, which would read as "stuck". SwiftUI's own repeating animation cannot be
/// retargeted like that mid-turn, which is why the motion is computed here.
public struct RefreshSpin: Equatable, Sendable {
    private var motion = Motion.resting(degrees: 0)

    /// Linear: constant motion for as long as the work lasts.
    static let secondsPerTurn: TimeInterval = 0.8
    /// Brief, so the icon is upright soon after the data lands.
    public static let settleDuration: TimeInterval = 0.25
    /// Degrees; far below what a 16 pt icon can show.
    private static let uprightTolerance = 0.5

    private enum Motion: Equatable, Sendable {
        case resting(degrees: Double)
        case spinning(fromDegrees: Double, since: Date)
        case settling(fromDegrees: Double, toDegrees: Double, since: Date)
    }

    public init() {}

    /// Does nothing while already spinning, so it can follow a refreshing flag that is set again unchanged.
    public mutating func start(at now: Date) {
        if case .spinning = motion { return }
        motion = .spinning(fromDegrees: degrees(at: now), since: now)
    }

    /// Does nothing unless spinning.
    public mutating func stop(at now: Date) {
        guard case .spinning = motion else { return }
        let reached = degrees(at: now)
        let upright = Self.nextUpright(after: reached)
        motion = upright > reached ? .settling(fromDegrees: reached, toDegrees: upright, since: now)
                                   : .resting(degrees: reached)
    }

    /// Turns a settle that is over into rest. The angle is the same either way; the change of value is what lets a
    /// view that pauses its timeline on `isMoving` redraw once more and pause.
    public mutating func finishSettling(at now: Date) {
        guard case .settling(_, let upright, _) = motion, !isMoving(at: now) else { return }
        motion = .resting(degrees: upright)
    }

    /// Only ever grows, so the icon never turns backwards.
    public func degrees(at now: Date) -> Double {
        switch motion {
        case .resting(let degrees):
            return degrees
        case .spinning(let start, let since):
            return start + max(now.timeIntervalSince(since), 0) / Self.secondsPerTurn * 360
        case .settling(let start, let end, let since):
            let progress = (now.timeIntervalSince(since) / Self.settleDuration).clamped(to: 0...1)
            return start + (end - start) * easeOut(progress)
        }
    }

    /// False once the icon is upright and still, so the timeline drawing it can pause.
    public func isMoving(at now: Date) -> Bool {
        switch motion {
        case .resting: false
        case .spinning: true
        case .settling(_, _, let since): now.timeIntervalSince(since) < Self.settleDuration
        }
    }

    /// The next whole turn at or after `degrees`. A hair past upright counts as upright: rounding it up would whip
    /// the icon through a whole extra turn because of timing noise.
    private static func nextUpright(after degrees: Double) -> Double {
        ((degrees - uprightTolerance) / 360).rounded(.up) * 360
    }
}

/// Cubic: fast at first, then decelerating into place, so the settle picks up the spin's momentum and lands softly.
private func easeOut(_ progress: Double) -> Double {
    1 - pow(1 - progress, 3)
}
