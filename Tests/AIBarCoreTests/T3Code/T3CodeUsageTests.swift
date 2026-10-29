import Foundation
import Testing
@testable import AIBarCore

// Method: write status files shaped like T3 Code's into a temporary caches directory and read them back through
// the cache, as the app does. Times are whole seconds before now, so a reading's age is exact and its date
// survives the round trip through ISO-8601.
@Suite struct T3CodeStatusReading {
    @Test func windowsAreToldApartByLengthAndKeepT3CodesIDs() throws {
        let cache = try T3CodeFixtures.cache(["claudeAgent": T3CodeFixtures.claude(checkedAt: minuteAgo)])
        defer { T3CodeFixtures.remove(cache) }

        let usage = try #require(cache.usage(of: "claudeAgent"))

        #expect(usage.checkedAt == minuteAgo)
        #expect(usage.windows.map(\.id) == ["five_hour", "seven_day", "seven_day_fable"])
        #expect(usage.windows.map(\.kind) == [.fiveHour, .weekly, .weeklyModel(name: "Fable")])
        #expect(usage.windows.map(\.title) == ["5-hour", "Weekly", "Weekly · Fable"])
        #expect(usage.windows.map(\.percentUsed) == [6, 77, 33])
    }

    // A weekly window T3 Code labels its own way is still weekly, so it gets a forecast; a month is not a length
    // AI Bar forecasts, so it is shown without one.
    @Test func windowsOfOtherProvidersKeepTheirLabels() throws {
        let cache = try T3CodeFixtures.cache(["antigravity": T3CodeFixtures.antigravity(checkedAt: minuteAgo)])
        defer { T3CodeFixtures.remove(cache) }

        let windows = try #require(cache.usage(of: "antigravity")).windows

        #expect(windows.map(\.kind) == [.weekly, .other])
        #expect(windows.map(\.title) == ["Claude & GPT (shared) · Weekly", "Monthly"])
        #expect(windows.last?.resetsAt == nil)
    }

    @Test func onlyTurnedOnInstancesWithUsageAreListed() throws {
        let cache = try T3CodeFixtures.cache([
            "antigravity": T3CodeFixtures.antigravity(checkedAt: minuteAgo),
            "codex_9887": T3CodeFixtures.signedOutCodexAccount,
            "cursor": T3CodeFixtures.disabledCursor(checkedAt: minuteAgo),
            "claudeAgent": T3CodeFixtures.claude(checkedAt: minuteAgo),
            "broken": "{not json",
        ])
        defer { T3CodeFixtures.remove(cache) }

        #expect(cache.instancesWithUsage().map(\.id) == ["antigravity", "claudeAgent"])
        #expect(cache.usage(of: "cursor") == nil)
        #expect(cache.usage(of: "codex_9887") == nil)
    }

    @Test func withoutT3CodeThereIsNothingToRead() {
        let cache = T3CodeProviderCache(directory: URL(filePath: "/nonexistent/AIBarCoreTests"))

        #expect(cache.instancesWithUsage().isEmpty)
        #expect(cache.usage(of: "claudeAgent") == nil)
    }

    @Test func theCachesLiveInT3CodeHome() {
        #expect(T3CodeProviderCache(environment: ["T3CODE_HOME": "/tmp/t3home"]).directory.path(percentEncoded: false)
                == "/tmp/t3home/caches/")
        #expect(T3CodeProviderCache(environment: [:]).directory
                == FileManager.default.homeDirectoryForCurrentUser.appending(path: ".t3/caches/"))
    }
}

// Method: put a T3 Code reading of a given age in front of a stand-in for the provider's own endpoint, and check
// which of the two the snapshot came from.
@Suite struct T3CodeFirstSource {
    @Test func aFreshReadingIsUsedUnderTheEndpointsNames() async throws {
        let cache = try T3CodeFixtures.cache(["claudeAgent": T3CodeFixtures.claude(checkedAt: minuteAgo)])
        defer { T3CodeFixtures.remove(cache) }
        let provider = T3CodeFirstUsageProvider(instanceID: "claudeAgent", cache: cache, direct: failingClaude,
                                                naming: { $0.namedLikeClaudeEndpoint() })

        let snapshot = try await provider.fetchUsage()

        #expect(snapshot.provider == ClaudeUsageProvider.providerID)
        #expect(snapshot.fetchedAt == minuteAgo)
        #expect(snapshot.windows.map(\.id) == ["session", "weekly_all", "weekly_scoped:Fable"])
        #expect(snapshot.primaryWindow?.percentUsed == 6)
    }

    @Test func chatGPTWindowsAreNamedByLengthAsTheEndpointNamesThem() async throws {
        let cache = try T3CodeFixtures.cache(["codex": T3CodeFixtures.codex(checkedAt: minuteAgo)])
        defer { T3CodeFixtures.remove(cache) }
        let provider = T3CodeFirstUsageProvider(instanceID: "codex", cache: cache, direct: failingClaude,
                                                naming: { $0.namedLikeChatGPTEndpoint() })

        #expect(try await provider.fetchUsage().windows.map(\.id) == ["weekly"])
    }

    // Seven minutes is past T3 Code's 5-minute refresh and the minute of slack: T3 Code has paused or quit.
    @Test(arguments: [7 * 60, 3 * 86_400] as [TimeInterval])
    func aStaleReadingDefersToTheEndpoint(age: TimeInterval) async throws {
        let cache = try T3CodeFixtures.cache(["claudeAgent": T3CodeFixtures.claude(checkedAt: now - age)])
        defer { T3CodeFixtures.remove(cache) }
        let direct = FakeUsageProvider(snapshot: .sample(fetchedAt: now))
        let provider = T3CodeFirstUsageProvider(instanceID: "claudeAgent", cache: cache, direct: direct,
                                                naming: { $0 })

        #expect(try await provider.fetchUsage() == .sample(fetchedAt: now))
    }

    @Test func withoutT3CodeTheEndpointIsAsked() async throws {
        let cache = T3CodeProviderCache(directory: URL(filePath: "/nonexistent/AIBarCoreTests"))
        let provider = T3CodeFirstUsageProvider(instanceID: "claudeAgent", cache: cache,
                                                direct: FakeUsageProvider(snapshot: .sample(fetchedAt: now)),
                                                naming: { $0 })

        #expect(try await provider.fetchUsage() == .sample(fetchedAt: now))
    }
}

// Method: build the app's provider list from a caches directory, as each refresh does.
@Suite struct ProvidersFoundInT3Code {
    @Test func everyOtherProviderT3CodeHasUsageForFollowsClaudeAndChatGPT() throws {
        let cache = try T3CodeFixtures.cache([
            "claudeAgent": T3CodeFixtures.claude(checkedAt: minuteAgo),
            "codex": T3CodeFixtures.codex(checkedAt: minuteAgo),
            "antigravity": T3CodeFixtures.antigravity(checkedAt: minuteAgo),
            "codex_9887": T3CodeFixtures.signedOutCodexAccount,
        ])
        defer { T3CodeFixtures.remove(cache) }

        let providers = UsageProviders.all(t3Code: cache)

        #expect(providers.map(\.id.rawValue) == ["claude", "chatgpt", "t3code:antigravity"])
        #expect(providers.map(\.displayName) == ["Claude", "ChatGPT", "Antigravity"])
        #expect(providers.map(\.defaultPlacement) == [.menuBar, .menuBar, .popoverOnly])
    }

    @Test func withoutT3CodeOnlyClaudeAndChatGPTAreShown() {
        let cache = T3CodeProviderCache(directory: URL(filePath: "/nonexistent/AIBarCoreTests"))

        #expect(UsageProviders.all(t3Code: cache).map(\.id.rawValue) == ["claude", "chatgpt"])
    }

    // T3 Code is the only source for these, so an old reading is still the best there is; its date says how old.
    @Test func aProviderOnlyInT3CodeShowsItsLastReadingHoweverOld() async throws {
        let dayAgo = now - 86_400
        let cache = try T3CodeFixtures.cache(["antigravity": T3CodeFixtures.antigravity(checkedAt: dayAgo)])
        defer { T3CodeFixtures.remove(cache) }
        let instance = try #require(cache.instancesWithUsage().first)

        let snapshot = try await T3CodeUsageProvider(instance: instance, cache: cache).fetchUsage()

        #expect(snapshot.provider == ProviderID("t3code:antigravity"))
        #expect(snapshot.fetchedAt == dayAgo)
    }

    @Test func aProviderT3CodeStopsReportingSaysSo() async throws {
        let cache = try T3CodeFixtures.cache(["antigravity": T3CodeFixtures.antigravity(checkedAt: minuteAgo)])
        defer { T3CodeFixtures.remove(cache) }
        let provider = T3CodeUsageProvider(instance: try #require(cache.instancesWithUsage().first), cache: cache)
        try FileManager.default.removeItem(at: cache.directory.appending(path: "antigravity.json"))

        await #expect(throws: T3CodeUsageError.self) { try await provider.fetchUsage() }
    }
}

/// Stands in for an endpoint that must not be reached.
private let failingClaude = ClaudeUsageProvider(credentials: NoCredentials(), transport: UnreachableTransport())

private struct NoCredentials: CredentialSource {
    func accessToken() async throws -> String { throw ClaudeUsageError.notLoggedIn }
}

private struct UnreachableTransport: HTTPTransport {
    func get(_ url: URL, headers: [String: String]) async throws -> (body: Data, status: Int) {
        throw URLError(.notConnectedToInternet)
    }
}

private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
private let minuteAgo = now - 60
