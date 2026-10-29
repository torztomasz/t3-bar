import Foundation
import Testing
@testable import T3BarCore

// Method: drive a spin with start and stop at chosen offsets from one fixed instant and read the angle back at other
// offsets, the way a display-linked timeline would. A turn takes 0.8 s, so 0.4 s is half a turn (180°). Angles are
// compared to a thousandth of a degree because `Date` offsets are not exact in binary.
@Suite struct RefreshSpinAngle {
    @Test func restsUprightBeforeAnyRefresh() {
        #expect(RefreshSpin().degrees(at: at(0)) == 0)
        #expect(!RefreshSpin().isMoving(at: at(0)))
    }

    @Test func turnsAtAConstantRateWhileRefreshing() {
        var spin = RefreshSpin()
        spin.start(at: at(0))

        #expect(isAbout(spin.degrees(at: at(0.4)), 180))
        #expect(isAbout(spin.degrees(at: at(1.2)), 540))
        #expect(spin.isMoving(at: at(10)))
    }

    // Stopping half a turn in still lands upright, one quarter of a second later.
    @Test func stoppingMidTurnSettlesOnTheNextFullTurn() {
        var spin = RefreshSpin()
        spin.start(at: at(0))
        spin.stop(at: at(0.4))

        #expect(isAbout(spin.degrees(at: at(0.4)), 180))
        #expect(isAbout(spin.degrees(at: at(0.65)), 360))
        #expect(isAbout(spin.degrees(at: at(5)), 360))
        #expect(!spin.isMoving(at: at(0.65)))
    }

    // Ease-out: most of the remaining turn is covered early, and the icon never runs past upright.
    @Test func settlingDeceleratesWithoutOvershooting() {
        var spin = RefreshSpin()
        spin.start(at: at(0))
        spin.stop(at: at(0.4))

        let halfwayThroughSettling = spin.degrees(at: at(0.525))
        #expect(halfwayThroughSettling > 270 && halfwayThroughSettling < 360)
        #expect(spin.isMoving(at: at(0.525)))
    }

    // Includes stopping a hair past upright, where timing noise would otherwise round up to another turn.
    @Test func stoppingOnAFullTurnDoesNotAddAnother() {
        var onTheTurn = RefreshSpin()
        onTheTurn.start(at: at(0))
        onTheTurn.stop(at: at(0.8))
        var justPastIt = RefreshSpin()
        justPastIt.start(at: at(0))
        justPastIt.stop(at: at(0.8001))

        #expect(isAbout(onTheTurn.degrees(at: at(2)), 360))
        #expect(abs(justPastIt.degrees(at: at(2)) - 360) < 0.5)
    }

    // A refresh that starts during the settle picks up from the current angle instead of jumping.
    @Test func restartingWhileSettlingContinuesFromTheCurrentAngle() {
        var spin = RefreshSpin()
        spin.start(at: at(0))
        spin.stop(at: at(0.4))
        let angleAtRestart = spin.degrees(at: at(0.5))
        spin.start(at: at(0.5))

        #expect(isAbout(spin.degrees(at: at(0.5)), angleAtRestart))
        #expect(isAbout(spin.degrees(at: at(0.9)), angleAtRestart + 180))
    }

    // A view pausing its timeline on `isMoving` needs a state change once the settle is over to redraw and pause;
    // finishing early must not cut the settle short.
    @Test func finishingTheSettleChangesTheSpinOnlyOnceItIsOver() {
        var spin = RefreshSpin()
        spin.start(at: at(0))
        spin.stop(at: at(0.4))
        let settling = spin

        spin.finishSettling(at: at(0.5))
        #expect(spin == settling)
        spin.finishSettling(at: at(0.65))
        #expect(spin != settling)
        #expect(isAbout(spin.degrees(at: at(0.66)), 360))
        #expect(!spin.isMoving(at: at(0.66)))
    }

    // Start and stop follow a refreshing flag that may be set again without changing.
    @Test func repeatedStartOrStopChangesNothing() {
        var spin = RefreshSpin()
        spin.stop(at: at(0))
        spin.start(at: at(0))
        spin.start(at: at(0.4))

        #expect(isAbout(spin.degrees(at: at(0.4)), 180))
    }
}

private let origin = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ seconds: Double) -> Date {
    origin.addingTimeInterval(seconds)
}

private func isAbout(_ degrees: Double, _ expected: Double) -> Bool {
    abs(degrees - expected) < 0.001
}
