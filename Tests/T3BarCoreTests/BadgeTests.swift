import Foundation
import Testing
@testable import T3BarCore

// Method (both suites): build the badge from hand-made windows and forecasts, the same inputs the app passes after a
// refresh, and assert on the exact text and size the menu bar would draw.
@Suite struct BadgeText {
    @Test func showsTheWindowPercentRoundedToAWholeNumber() {
        #expect(UsageText.badge(window: .fiveHour(percent: 42.4), hasError: false) == "42%")
        #expect(UsageText.badge(window: .fiveHour(percent: 41.6), hasError: false) == "42%")
    }

    // Before the first successful fetch there is nothing to show, but the item must keep its place in the menu bar.
    @Test func showsPlaceholderBeforeAnyData() {
        #expect(UsageText.badge(window: nil, hasError: false) == "--%")
    }

    @Test func marksThePlaceholderWhenFetchingFailed() {
        #expect(UsageText.badge(window: nil, hasError: true) == "--%!")
    }

    // A failed refresh keeps the last snapshot; its percent is still the best number available.
    @Test func keepsShowingTheLastPercentWhenARefreshFailed() {
        #expect(UsageText.badge(window: .fiveHour(percent: 42), hasError: true) == "42%")
    }
}

// Method: menu bar heights are the ones macOS reports (points between a screen's top and its visible frame); each
// test says which display they stand for. The expected heights follow from the camera pill's 24 pt and a 2 pt
// margin above and below.
@Suite struct BadgeHeightForMenuBars {
    // An external display (30 pt bar) and a notched built-in one (33 pt): both leave room for the full pill height.
    @Test func matchesTheCameraPillWhereTheMenuBarHasRoom() {
        #expect(BadgeSize.height(menuBarHeights: [30, 33]) == 24)
    }

    // A 24 pt bar on a non-notched display would be filled edge to edge, so the badge shrinks to keep its margins.
    @Test func shrinksToKeepAMarginOnAShortMenuBar() {
        #expect(BadgeSize.height(menuBarHeights: [24]) == 20)
    }

    // One image is shown on every display's menu bar, so it has to fit the shortest.
    @Test func fitsTheShortestMenuBarWhenDisplaysDiffer() {
        #expect(BadgeSize.height(menuBarHeights: [24, 33]) == 20)
    }

    // A menu bar hidden by a full-screen app reports no height; it is no reason to shrink the badge.
    @Test func ignoresHiddenMenuBars() {
        #expect(BadgeSize.height(menuBarHeights: [0, 30]) == 24)
        #expect(BadgeSize.height(menuBarHeights: []) == 24)
    }
}

// Method: lay out badges of the two heights `BadgeSize` produces (24 pt, and 20 pt on a short menu bar) and check
// the rows against the badge's edges. A row of digits is as tall as the font's capital letters, about 0.72 of the
// font size for the system font, which is what has to clear the neighbouring row and the edges. The edges are where
// the refresh light runs, 1.5 pt wide at its thinnest.
@Suite struct BadgeLayoutForProviders {
    @Test func aSingleReadingIsCentredAtFullSizeWithoutAMark() {
        #expect(BadgeLayout(rowCount: 1, height: 24)
                == BadgeLayout(fontSize: 12, markSize: nil, rowMidlines: [12]))
    }

    // The outline the refresh light follows is a capsule only while the corners are empty.
    @Test func onlySeveralReadingsCountAsStacked() {
        #expect(!BadgeLayout(rowCount: 1, height: 24).isStacked)
        #expect(BadgeLayout(rowCount: 2, height: 24).isStacked)
    }

    @Test func twoReadingsAreStackedAroundTheMiddleInSmallerType() {
        #expect(BadgeLayout(rowCount: 2, height: 24)
                == BadgeLayout(fontSize: 9.5, markSize: 8, rowMidlines: [16.75, 7.25]))
    }

    @Test func rowsMoveCloserTogetherInAShortBadge() {
        #expect(BadgeLayout(rowCount: 2, height: 20).rowMidlines == [14.5, 5.5])
    }

    @Test(arguments: [20.0, 24.0])
    func stackedDigitsAndMarksStayClearOfTheRefreshLightAndOfEachOther(height: Double) throws {
        let layout = BadgeLayout(rowCount: 2, height: height)
        let rowHeight = max(layout.fontSize * 0.72, try #require(layout.markSize))
        let (top, bottom) = (layout.rowMidlines[0], layout.rowMidlines[1])

        let lightWidth = 1.5

        #expect(top + rowHeight / 2 <= height - lightWidth)
        #expect(bottom - rowHeight / 2 >= lightWidth)
        #expect(top - bottom >= rowHeight + 1)
    }
}
