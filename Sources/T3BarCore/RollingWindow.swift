import Foundation

/// Timing of rolling usage windows, kept in one place so the estimator and the sample store agree on which samples
/// belong to the current window.
public enum RollingWindow {
    /// Claude's and ChatGPT's session limits reset 5 hours after the request that opened the window.
    public static let fiveHours: TimeInterval = 5 * secondsPerHour
    /// Weekly limits, overall and per model, reset 7 days after the window opened.
    public static let week: TimeInterval = 7 * day

    static let secondsPerHour: TimeInterval = 3600
    static let day: TimeInterval = 24 * secondsPerHour

    static func start(resetsAt: Date, length: TimeInterval) -> Date {
        resetsAt.addingTimeInterval(-length)
    }
}
