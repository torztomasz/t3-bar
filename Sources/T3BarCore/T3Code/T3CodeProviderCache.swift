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

    public init(home: T3CodeHome = T3CodeHome()) {
        self.init(directory: home.caches)
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
        try JSONDecoder.t3Code.decode(T3CodeProviderStatus.self, from: data).instance
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

/// The subset of T3 Code's provider status file the app reads. Optional where T3 Code's own schema is, so a field
/// T3 Code leaves out costs that field, not the instance.
private struct T3CodeProviderStatus: Decodable {
    let instanceId: String
    let driver: String
    let displayName: String?
    let enabled: Bool?
    let usageLimits: T3CodeUsageLimits?

    var instance: T3CodeProviderInstance {
        T3CodeProviderInstance(id: instanceId, driver: driver, displayName: displayName ?? instanceId,
                               isEnabled: enabled ?? false, usage: usageLimits?.usage)
    }
}
