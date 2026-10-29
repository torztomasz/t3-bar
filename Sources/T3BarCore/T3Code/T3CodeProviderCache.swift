import Foundation

/// The usage T3 Code already tracks for every provider it runs, read from the status file it keeps per provider
/// instance (`<T3CODE_HOME>/caches/<instance>.json`). Nothing to set up: T3 Code's own sessions and probes fill the
/// files, and the app only reads them.
///
/// The files are T3 Code's internal cache rather than a published API, so reading is best effort: a file that is
/// missing, unreadable or shaped differently reads as "no reading".
public struct T3CodeProviderCache: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `T3CODE_HOME` is the variable T3 Code itself honours; without it T3 Code lives in `~/.t3`.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let home = environment["T3CODE_HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".t3", directoryHint: .isDirectory)
        self.init(directory: home.appending(path: "caches", directoryHint: .isDirectory))
    }

    /// Every instance T3 Code has turned on that has usage to show: the built-in ones first, then the rest by id, so
    /// the list is stable.
    public func instancesWithUsage() -> [T3CodeProviderInstance] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? Self.instance(fromStatusJSON: Data(contentsOf: $0)) }
            .filter { $0.isEnabled && $0.usage != nil }
            .sorted { ($0.builtInRank, $0.id) < ($1.builtInRank, $1.id) }
    }

    /// Nil when T3 Code has no reading for `instanceID`: never ran it, turned it off, or could not probe it yet.
    public func usage(of instanceID: String) -> T3CodeUsage? {
        let file = directory.appending(path: "\(instanceID).json", directoryHint: .notDirectory)
        guard let instance = try? Self.instance(fromStatusJSON: Data(contentsOf: file)),
              instance.id == instanceID, instance.isEnabled else { return nil }
        return instance.usage
    }

    static func instance(fromStatusJSON data: Data) throws -> T3CodeProviderInstance {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseISODate(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Not an ISO-8601 date: \(text)"))
            }
            return date
        }
        return try decoder.decode(T3CodeProviderStatus.self, from: data).instance
    }
}

/// One provider instance as T3 Code configures it, e.g. the default Claude, or a second Codex account.
public struct T3CodeProviderInstance: Equatable, Sendable {
    /// T3 Code's instance id, e.g. `"claudeAgent"` or `"codex_77f2…"`; stable across launches.
    public let id: String
    /// Which provider runs it, e.g. `"claudeAgent"`, `"codex"`, `"antigravity"`.
    public let driver: String
    /// The name the user sees in T3 Code, e.g. `"ChatGPT - Work"`.
    public let displayName: String
    public let isEnabled: Bool
    /// Nil while there is no window to show.
    public let usage: T3CodeUsage?

    /// The instances T3 Code creates out of the box, for Claude and for Codex, in the order the app lists them.
    public static let builtInIDs = ["claudeAgent", "codex"]

    var builtInRank: Int {
        Self.builtInIDs.firstIndex(of: id) ?? Self.builtInIDs.count
    }
}

/// The windows of one instance as T3 Code last saw them.
public struct T3CodeUsage: Equatable, Sendable {
    /// When T3 Code took the reading; it may be long ago if T3 Code has not run since.
    public let checkedAt: Date
    public let windows: [UsageWindow]
}

/// The subset of T3 Code's provider status file the app reads. Optional where T3 Code's own schema is, so a field
/// T3 Code leaves out costs that field, not the instance.
private struct T3CodeProviderStatus: Decodable {
    let instanceId: String
    let driver: String
    let displayName: String?
    let enabled: Bool?
    let usageLimits: UsageLimits?

    struct UsageLimits: Decodable {
        let checkedAt: Date
        let windows: [Window]
    }

    struct Window: Decodable {
        let id: String
        let label: String
        let usedPercent: Double
        let resetsAt: Date?
        let windowDurationMins: Int?
    }

    var instance: T3CodeProviderInstance {
        let windows = usageLimits?.windows.map(\.window) ?? []
        return T3CodeProviderInstance(
            id: instanceId, driver: driver, displayName: displayName ?? instanceId, isEnabled: enabled ?? false,
            usage: usageLimits.flatMap { windows.isEmpty ? nil : T3CodeUsage(checkedAt: $0.checkedAt, windows: windows) })
    }
}

extension T3CodeProviderStatus.Window {
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

/// T3 Code writes millisecond fractions (`2026-10-29T15:50:00.454Z`), but a whole-second timestamp is equally valid
/// ISO-8601, so both are accepted rather than dropping the date.
private func parseISODate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}
