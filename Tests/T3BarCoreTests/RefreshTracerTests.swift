import Foundation
import Testing
@testable import T3BarCore

// Method: drive a tracer with start and stop at chosen offsets from one fixed instant and read the lit segment back at
// other offsets, the way a display link would. A lap takes 0.9 s and the light is 0.28 of a lap long, so 0.45 s is half
// a lap and the tail drains away 0.252 s after the head stops. Positions are compared to a millionth of a lap because
// `Date` offsets are not exact in binary.
@Suite struct RefreshTracerSegment {
    @Test func nothingIsLitBeforeAnyRefresh() {
        #expect(RefreshTracer().segment(at: at(0)) == nil)
        #expect(!RefreshTracer().isMoving(at: at(0)))
    }

    // The light grows out of the starting point rather than appearing at full length.
    @Test func setsOffFromTheStartingPoint() {
        var tracer = RefreshTracer()
        tracer.start(at: at(0))

        #expect(isAbout(tracer.segment(at: at(0.09)), tail: 0, head: 0.1))
        #expect(isAbout(tracer.segment(at: at(0.45)), tail: 0.22, head: 0.5))
    }

    @Test func runsAtAConstantPaceWhileRefreshing() {
        var tracer = RefreshTracer()
        tracer.start(at: at(0))

        #expect(isAbout(tracer.segment(at: at(1.8)), tail: 1.72, head: 2))
        #expect(tracer.isMoving(at: at(60)))
    }

    // Vanishing mid-lap would read as cut off, so the head runs on to the end of its lap and holds there, and the
    // tail keeps running until it reaches it.
    @Test func stoppingMidLapFinishesTheLapThenDrainsAtTheStartingPoint() {
        var tracer = RefreshTracer()
        tracer.start(at: at(0))
        tracer.stop(at: at(0.45))

        #expect(isAbout(tracer.segment(at: at(0.45)), tail: 0.22, head: 0.5))
        #expect(isAbout(tracer.segment(at: at(0.9)), tail: 0.72, head: 1))
        #expect(isAbout(tracer.segment(at: at(1.08)), tail: 0.92, head: 1))
        #expect(tracer.segment(at: at(0.9 + 0.253)) == nil)
        #expect(!tracer.isMoving(at: at(5)))
    }

    // The light must go out on a clock when the display link drawing it stops firing, so the clock has to agree with
    // the segment: still lit a hair before, gone from then on.
    @Test func goesOutWhenTheDrainingLightIsGone() throws {
        var tracer = RefreshTracer()
        tracer.start(at: at(0))
        #expect(tracer.goesOutAt == nil)
        tracer.stop(at: at(0.45))

        let goesOutAt = try #require(tracer.goesOutAt)
        #expect(abs(goesOutAt.timeIntervalSince(at(0.9 + 0.252))) < 1e-6)
        #expect(tracer.segment(at: goesOutAt.addingTimeInterval(-0.001)) != nil)
        #expect(tracer.segment(at: goesOutAt) == nil)
    }

    // A refresh far shorter than a lap would otherwise be a flicker.
    @Test func aRefreshShorterThanALapStillShowsAWholeLap() {
        var tracer = RefreshTracer()
        tracer.start(at: at(0))
        tracer.stop(at: at(0.01))

        #expect(isAbout(tracer.segment(at: at(0.9)), tail: 0.72, head: 1))
        #expect(tracer.isMoving(at: at(1.1)))
        #expect(!tracer.isMoving(at: at(1.16)))
    }

    // Stopping while the tail is still in the previous lap finishes the head's lap, not the tail's.
    @Test func stoppingJustAfterTheStartingPointFinishesTheNewLap() {
        var tracer = RefreshTracer()
        tracer.start(at: at(0))
        tracer.stop(at: at(0.99))

        #expect(isAbout(tracer.segment(at: at(1.8)), tail: 1.72, head: 2))
        #expect(!tracer.isMoving(at: at(1.8 + 0.253)))
    }

    // A refresh that starts while the light drains picks up from where it is instead of jumping: the head sets off
    // again, and the tail waits until the light is back to full length.
    @Test func restartingWhileDrainingContinuesFromTheCurrentSegment() {
        var tracer = RefreshTracer()
        tracer.start(at: at(0))
        tracer.stop(at: at(0.45))
        tracer.start(at: at(1.08))

        #expect(isAbout(tracer.segment(at: at(1.08)), tail: 0.92, head: 1))
        #expect(isAbout(tracer.segment(at: at(1.17)), tail: 0.92, head: 1.1))
        #expect(isAbout(tracer.segment(at: at(1.53)), tail: 1.22, head: 1.5))
    }

    // Start and stop follow a refreshing flag that may be set again without changing.
    @Test func repeatedStartOrStopChangesNothing() {
        var tracer = RefreshTracer()
        tracer.stop(at: at(0))
        tracer.start(at: at(0))
        tracer.start(at: at(0.45))

        #expect(isAbout(tracer.segment(at: at(0.45)), tail: 0.22, head: 0.5))
    }
}

@Suite struct RefreshTracerStroke {
    @Test func aSegmentWithinOneLapMapsOntoTheFirstTimeRound() {
        let stroke = RefreshTracer.Segment(tail: 2.2, head: 2.48).strokeOnDoubledOutline

        #expect(abs(stroke.lowerBound - 0.1) < 1e-9 && abs(stroke.upperBound - 0.24) < 1e-9)
    }

    // Past the starting point the head continues onto the second time round, so the stroke stays in one piece.
    @Test func aSegmentAcrossTheStartingPointRunsOnIntoTheSecondTimeRound() {
        let stroke = RefreshTracer.Segment(tail: 2.9, head: 3.1).strokeOnDoubledOutline

        #expect(abs(stroke.lowerBound - 0.45) < 1e-9 && abs(stroke.upperBound - 0.55) < 1e-9)
    }
}

private let origin = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ seconds: Double) -> Date {
    origin.addingTimeInterval(seconds)
}

private func isAbout(_ segment: RefreshTracer.Segment?, tail: Double, head: Double) -> Bool {
    guard let segment else { return false }
    return abs(segment.tail - tail) < 1e-6 && abs(segment.head - head) < 1e-6
}
