import Foundation
import Testing
@testable import T3BarCore

// Method: feed frames shaped like the ones T3 Code's server sends on the config stream (captured live, trimmed, and
// for hubs written from T3 Code's `UsageLimitSourceSnapshots` schema, since no hub was connected) and check what the
// subscription takes from each.
@Suite struct T3CodeServerFrames {
    @Test func aHubEventGivesItsAccountsWithTheirUsage() throws {
        let frame = T3CodeServerMessage(.string(chunk(hubEvent)))

        let hub = try #require(frame.hubs?.first)
        #expect(hub.id == "home")
        #expect(hub.label == "hub.local")
        #expect(hub.accounts.map(\.id) == ["claude-a.json", "codex-b.json"])
        #expect(hub.accounts.map(\.driver) == ["claudeAgent", "codex"])
        #expect(hub.accounts.map(\.email) == ["a@example.com", nil])
        #expect(hub.accounts.first?.usage?.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(frame.needsAck)
        #expect(!frame.endsStream)
    }

    // The snapshot opens the stream and is far bigger than this; a field the app cannot read must not matter.
    @Test func aChunkWithoutAHubEventStillNeedsAnAck() {
        let frame = T3CodeServerMessage(.string(chunk(#"{"version":1,"type":"snapshot","config":{"providers":[{}]}}"#)))

        #expect(frame.hubs == nil)
        #expect(frame.needsAck)
    }

    // T3 Code reports "no hubs" as an empty list, which must clear any shown before.
    @Test func noHubsIsAnEmptyListNotNothing() {
        let frame = T3CodeServerMessage(.string(chunk(#"{"type":"usageLimitSourcesUpdated","payload":{"sources":[]}}"#)))

        #expect(frame.hubs == [])
    }

    @Test func anAccountTheAppCannotReadIsSkippedNotTheHub() {
        let frame = T3CodeServerMessage(.string(chunk(#"""
            {"type":"usageLimitSourcesUpdated","payload":{"sources":[{"id":"home","label":"hub.local","accounts":[
              {"id":"odd.json","driver":"codex","usageLimits":{"checkedAt":"yesterday","windows":[]}},
              {"id":"fine.json","driver":"codex"}]}]}}
            """#)))

        #expect(frame.hubs?.first?.accounts.map(\.id) == ["fine.json"])
    }

    @Test func theLastHubEventInAChunkWins() {
        let frame = T3CodeServerMessage(.string(chunk(
            #"{"type":"usageLimitSourcesUpdated","payload":{"sources":[]}}"#, hubEvent)))

        #expect(frame.hubs?.count == 1)
    }

    @Test func anExitEndsTheStream() {
        let exit = #"{"_tag":"Exit","requestId":"1","exit":{"_tag":"Success","value":null}}"#

        let frame = T3CodeServerMessage(.string(exit))

        #expect(frame.endsStream)
        #expect(!frame.needsAck)
    }

    @Test(arguments: [#"{"_tag":"Pong"}"#, #"{"_tag":"Chunk","requestId":"7","values":[]}"#, "not json"])
    func framesForSomethingElseChangeNothing(_ text: String) {
        let frame = T3CodeServerMessage(.string(text))

        #expect(frame.hubs == nil)
        #expect(!frame.needsAck)
        #expect(!frame.endsStream)
    }

    @Test func theStreamURLCarriesTheProtocolVersion() {
        #expect(T3CodeServerMessage.streamURL(origin: URL(string: "http://127.0.0.1:3773")!).absoluteString
                == "ws://127.0.0.1:3773/ws?orchestrationProtocol=2")
    }
}

// Method: set the hubs as the subscription would, then build the provider list and read usage through it.
@Suite struct ProvidersFromHubs {
    @Test func everyAccountWithUsageIsAProviderAfterT3CodesOwn() throws {
        let cache = try T3CodeFixtures.cache(["claudeAgent": T3CodeFixtures.claude(checkedAt: Date())])
        defer { T3CodeFixtures.remove(cache) }
        let hubs = T3CodeHubs()
        _ = hubs.update(try #require(T3CodeServerMessage(.string(chunk(hubEvent))).hubs))

        let providers = UsageProviders.all(t3Code: cache, hubs: hubs)

        #expect(providers.map(\.id.rawValue) == ["claudeAgent", "cliproxy:home:claude-a.json"])
        #expect(providers.last?.displayName == "Claude (a@example.com)")
        #expect(providers.last?.driver == "claudeAgent")
        #expect(providers.last?.defaultPlacement == .popoverOnly)
        #expect(providers.last?.pool == UsagePool(id: "cliproxy:home", name: "hub.local"))
        #expect(providers.first?.pool == nil)
    }

    @Test func anAccountReadsItsLatestUsage() async throws {
        let hubs = T3CodeHubs()
        _ = hubs.update(try #require(T3CodeServerMessage(.string(chunk(hubEvent))).hubs))
        let provider = try #require(UsageProviders.all(t3Code: emptyCache, hubs: hubs).first)

        let snapshot = try await provider.fetchUsage()

        #expect(snapshot.windows.map(\.percentUsed) == [42, 10])
        #expect(snapshot.fetchedAt == ISO8601DateFormatter().date(from: "2026-10-29T12:00:00Z"))
    }

    @Test func anAccountGoneFromItsHubSaysSo() async throws {
        let hubs = T3CodeHubs()
        _ = hubs.update(try #require(T3CodeServerMessage(.string(chunk(hubEvent))).hubs))
        let provider = try #require(UsageProviders.all(t3Code: emptyCache, hubs: hubs).first)
        _ = hubs.update([])

        await #expect(throws: T3CodeUsageError.self) { try await provider.fetchUsage() }
    }

    @Test func updatingTellsWhetherAnythingChanged() {
        let hubs = T3CodeHubs()

        #expect(!hubs.update([]))
        #expect(hubs.update([T3CodeHub(id: "home", label: "hub.local", accounts: [], error: nil)]))
        #expect(!hubs.update([T3CodeHub(id: "home", label: "hub.local", accounts: [], error: nil)]))
    }

    // As T3 Code reported a hub whose management key the hub refused.
    @Test func aHubT3CodeCannotReadShowsWhy() async throws {
        let hubs = T3CodeHubs()
        _ = hubs.update(try #require(T3CodeServerMessage(.string(chunk(#"""
            {"type":"usageLimitSourcesUpdated","payload":{"sources":[{"id":"cliproxy-vps-8317","kind":"cliproxy",
             "label":"Codex (pool)","checkedAt":"2026-10-29T12:15:49.140Z","accounts":[],
             "error":"The hub answered with HTTP 401."}]}}
            """#))).hubs))
        let provider = try #require(UsageProviders.all(t3Code: emptyCache, hubs: hubs).first)

        #expect(provider.displayName == "Codex (pool)")
        #expect(provider.defaultPlacement == .popoverOnly)
        let error = await #expect(throws: T3CodeUsageError.self) { try await provider.fetchUsage() }
        #expect(error?.errorDescription == "T3 Code can't read this hub's accounts: The hub answered with HTTP 401.")
    }
}

// Method: name accounts as a hub lists them and read the names back, checking each stays short but tells the
// account apart from the rest of the hub.
@Suite struct HubAccountNames {
    @Test func anAccountShowsItsProviderAndTheStartOfItsEmail() {
        #expect(names(("codex", "tomasz.torz@l2beat.com"), ("codex", "tomasz.michal.torz@gmail.com"))
                == ["Codex (to…@l2beat.com)", "Codex (to…@gmail.com)"])
    }

    // Both would read `to…@gmail.com`; `tomasz.m` and `tomasz.t` are where they part.
    @Test func accountsOnOneDomainShowAsMuchAsTellsThemApart() {
        #expect(names(("codex", "tomasz.michal@gmail.com"), ("claudeAgent", "tomasz.torz@gmail.com"))
                == ["Codex (tomasz.m…@gmail.com)", "Claude (tomasz.t…@gmail.com)"])
    }

    @Test func aShortAddressIsShownWhole() {
        #expect(names(("codex", "ab@x.io"), ("codex", "a@y.io")) == ["Codex (ab@x.io)", "Codex (a@y.io)"])
    }

    // One address signed in to both providers: the provider already tells them apart.
    @Test func theSameEmailForTwoProvidersIsShortenedAsUsual() {
        #expect(names(("codex", "tomasz@gmail.com"), ("claudeAgent", "tomasz@gmail.com"))
                == ["Codex (to…@gmail.com)", "Claude (to…@gmail.com)"])
    }

    @Test func withoutAnEmailTheHubsIDStandsIn() {
        #expect(names(("codex", nil)) == ["Codex (codex-1.json)"])
    }

    private func names(_ accounts: (driver: String, email: String?)...) -> [String] {
        T3CodeHubAccount.names(of: accounts.enumerated().map { index, account in
            T3CodeHubAccount(id: "\(account.driver)-\(index + 1).json", driver: account.driver, email: account.email,
                             usage: nil)
        })
    }
}

private func chunk(_ events: String...) -> String {
    #"{"_tag":"Chunk","requestId":"1","values":[\#(events.joined(separator: ","))]}"#
}

/// One hub with a Claude account that has usage and a Codex account T3 Code could not read yet.
private let hubEvent = """
    {"version":1,"type":"usageLimitSourcesUpdated","payload":{"sources":[
      {"id":"home","kind":"cliproxy","label":"hub.local","checkedAt":"2026-10-29T12:00:00.000Z","accounts":[
        {"id":"claude-a.json","driver":"claudeAgent","email":"a@example.com","plan":"Claude Subscription",
         "usageLimits":{"checkedAt":"2026-10-29T12:00:00.000Z","windows":[
           {"id":"five_hour","kind":"session","label":"Session","usedPercent":42,"windowDurationMins":300,
            "resetsAt":"2026-10-29T15:00:00.000Z"},
           {"id":"seven_day","kind":"weekly","label":"Weekly","usedPercent":10,"windowDurationMins":10080}]}},
        {"id":"codex-b.json","driver":"codex",
         "usageLimits":{"checkedAt":"2026-10-29T12:00:00.000Z","windows":[]}}]}]}}
    """

private let emptyCache = T3CodeProviderCache(directory: URL(filePath: "/nonexistent/T3BarCoreTests"))
