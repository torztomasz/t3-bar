/// How tall the menu bar badge is drawn. Pure, so the fit to short and tall menu bars is unit-tested without AppKit.
///
/// The badge copies the system camera indicator beside it. Measured in `tickets/005-reference-camera-pill.png`,
/// which is 1 px per point (the 18 pt badge of the time is 18 px tall there), the pill is 24 pt tall. A non-notched
/// display's menu bar is itself only 24 pt tall, so the badge gives up height before its margins.
public enum BadgeSize {
    static let cameraPillHeight: Double = 24
    /// Clear space above and below, so the capsule never touches the menu bar's edges.
    static let margin: Double = 2

    /// `menuBarHeights` has one entry per display; a hidden menu bar (full-screen app) reports 0 and is ignored.
    /// `NSStatusBar.thickness` is not used because it still reports the legacy 22 pt on menu bars of 30 pt and more.
    public static func height(menuBarHeights: [Double]) -> Double {
        guard let shortest = menuBarHeights.filter({ $0 > 0 }).min() else { return cameraPillHeight }
        return min(cameraPillHeight, shortest - 2 * margin)
    }
}
