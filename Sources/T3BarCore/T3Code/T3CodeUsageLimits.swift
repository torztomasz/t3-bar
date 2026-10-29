import Foundation

/// The windows of one provider or hub account as T3 Code last saw them.
public struct T3CodeUsage: Equatable, Sendable {
    /// When T3 Code took the reading; it may be long ago if T3 Code has not run since.
    public let checkedAt: Date
    public let windows: [UsageWindow]
}

/// T3 Code's `usageLimits` object, which its status files and its server stream share.
struct T3CodeUsageLimits: Decodable {
    let checkedAt: Date
    let windows: [Window]

    struct Window: Decodable {
        let id: String
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
        let windowDurationMins: Int?
    }

    /// Nil without a window, which leaves nothing to show.
    var usage: T3CodeUsage? {
        windows.isEmpty ? nil : T3CodeUsage(checkedAt: checkedAt, windows: windows.map(\.window))
    }
}

extension T3CodeUsageLimits.Window {
    /// Told apart by length rather than by T3 Code's `kind`, because the length is what the forecast needs and T3
    /// Code labels a weekly cap on one model `Weekly · <model>`.
    var window: UsageWindow {
        let kind: UsageWindow.Kind = switch windowDurationMins.map({ TimeInterval($0 * 60) }) {
        case RollingWindow.fiveHours: .fiveHour
        case RollingWindow.week:
            label.hasPrefix(Self.modelLabelPrefix)
                ? .weeklyModel(name: String(label.dropFirst(Self.modelLabelPrefix.count))) : .weekly
        default: .other
        }
        // T3 Code calls the 5-hour window "Session"; the rest of the app calls it by its length.
        return UsageWindow(id: id, kind: kind, title: kind == .fiveHour ? "5-hour" : label,
                           percentUsed: usedPercent, resetsAt: resetsAt)
    }

    private static let modelLabelPrefix = "Weekly · "
}

extension JSONDecoder {
    /// Reads T3 Code's dates, which are ISO-8601 strings.
    static var t3Code: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseISODate(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Not an ISO-8601 date: \(text)"))
            }
            return date
        }
        return decoder
    }
}

/// T3 Code writes millisecond fractions (`2026-10-29T15:50:00.454Z`), but a whole-second timestamp is equally valid
/// ISO-8601, so both are accepted rather than dropping the date.
private func parseISODate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}
