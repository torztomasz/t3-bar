import Foundation
@testable import T3BarCore

/// Provider status files shaped like the ones T3 Code writes under `~/.t3/caches`, cut down to the fields around
/// `usageLimits` and stripped of account details. `checkedAt` is a parameter so tests can make a reading fresh or
/// stale against the real clock.
enum T3CodeFixtures {
    static func claude(checkedAt: Date) -> String {
        """
        {"displayName":"Claude","enabled":true,"installed":true,"status":"ready","instanceId":"claudeAgent",
         "driver":"claudeAgent","models":[{"slug":"claude-opus-5-5"}],
         "usageLimits":{"checkedAt":"\(iso(checkedAt))","windows":[
           {"id":"five_hour","kind":"session","label":"Session","windowDurationMins":300,"usedPercent":6,
            "resetsAt":"2026-10-29T15:50:00.454Z"},
           {"id":"seven_day","kind":"weekly","label":"Weekly","windowDurationMins":10080,"usedPercent":77,
            "resetsAt":"2026-10-30T00:00:00.000Z"},
           {"id":"seven_day_fable","kind":"weekly","label":"Weekly · Fable","windowDurationMins":10080,
            "usedPercent":33,"resetsAt":"2026-10-30T00:00:00.454Z"}]}}
        """
    }

    static func codex(checkedAt: Date) -> String {
        """
        {"displayName":"Codex","enabled":true,"instanceId":"codex","driver":"codex",
         "usageLimits":{"checkedAt":"\(iso(checkedAt))","windows":[
           {"id":"primary","kind":"weekly","label":"Weekly","usedPercent":12,"windowDurationMins":10080,
            "resetsAt":"2026-11-05T10:28:08.000Z"}],
          "resetCredits":{"availableCount":0}}}
        """
    }

    static func antigravity(checkedAt: Date) -> String {
        """
        {"displayName":"Antigravity","enabled":true,"instanceId":"antigravity","driver":"antigravity",
         "usageLimits":{"checkedAt":"\(iso(checkedAt))","windows":[
           {"id":"3p-weekly","label":"Claude & GPT (shared) · Weekly","kind":"weekly","usedPercent":4,
            "resetsAt":"2026-11-05T11:11:11.000Z","windowDurationMins":10080},
           {"id":"monthly","label":"Monthly","kind":"monthly","usedPercent":20,"windowDurationMins":43200}],
          "credentialFingerprint":"8a62"}}
        """
    }

    /// A second Codex account T3 Code has set up but not signed in: no usage yet.
    static let signedOutCodexAccount = """
        {"displayName":"ChatGPT - Work","enabled":true,"instanceId":"codex_9887","driver":"codex",
         "status":"warning","auth":{"status":"unauthenticated"}}
        """

    static func disabledCursor(checkedAt: Date) -> String {
        """
        {"displayName":"Cursor","enabled":false,"instanceId":"cursor","driver":"cursor",
         "usageLimits":{"checkedAt":"\(iso(checkedAt))","windows":[
           {"id":"plan","label":"Plan","kind":"monthly","usedPercent":50}]}}
        """
    }

    /// A temporary caches directory holding `files` (instance id → JSON), removed by `defer`-ing `remove(_:)`.
    static func cache(_ files: [String: String]) throws -> T3CodeProviderCache {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "T3BarCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (instanceID, json) in files {
            try Data(json.utf8).write(to: directory.appending(path: "\(instanceID).json"))
        }
        return T3CodeProviderCache(directory: directory)
    }

    static func remove(_ cache: T3CodeProviderCache) {
        try? FileManager.default.removeItem(at: cache.directory)
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
