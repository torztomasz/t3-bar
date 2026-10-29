/// Where the menu bar badge puts its readings. Pure, so the fit of two rows into short and tall badges is
/// unit-tested without AppKit.
///
/// One reading is drawn at the menu bar's own text size. Several are stacked in smaller type, each behind its
/// provider's mark, so the badge stays as narrow as a single reading.
public struct BadgeLayout: Equatable, Sendable {
    public let fontSize: Double
    /// Side of the square a provider's mark is drawn in; nil for a single reading, which needs no telling apart.
    public let markSize: Double?
    /// Each row's vertical middle, measured from the badge's bottom edge, top row first.
    public let rowMidlines: [Double]

    public static let markSpacing: Double = 3

    static let singleRowFontSize: Double = 12
    /// The largest size at which two rows of digits clear each other in a 20 pt badge.
    static let stackedFontSize: Double = 9.5
    static let stackedMarkSize: Double = 8
    /// Rows this far apart keep marks and digits clear of their neighbours, and in a badge of full height leave
    /// the refresh light, which runs along the badge's edges, a gap of its own.
    static let stackedRowPitch: Double = 9.5
    /// The least room the outer rows leave at the badge's top and bottom: the refresh light's width.
    static let edgeClearance: Double = 1.5

    init(fontSize: Double, markSize: Double?, rowMidlines: [Double]) {
        self.fontSize = fontSize
        self.markSize = markSize
        self.rowMidlines = rowMidlines
    }

    /// Stacked readings reach into the corners a capsule would cut off, so their outline needs tighter corners.
    public var isStacked: Bool {
        rowMidlines.count > 1
    }

    public init(rowCount: Int, height: Double) {
        guard rowCount > 1 else {
            self.init(fontSize: Self.singleRowFontSize, markSize: nil, rowMidlines: [height / 2])
            return
        }
        let roomForMidlines = height - Self.stackedMarkSize - 2 * Self.edgeClearance
        let pitch = min(Self.stackedRowPitch, roomForMidlines / Double(rowCount - 1))
        let topMidline = height / 2 + pitch * Double(rowCount - 1) / 2
        self.init(fontSize: Self.stackedFontSize, markSize: Self.stackedMarkSize,
                  rowMidlines: (0..<rowCount).map { topMidline - pitch * Double($0) })
    }
}
