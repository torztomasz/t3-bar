import Foundation
import Testing
@testable import T3BarCore

// Method: drive the fake only through the `UsageProvider` protocol, the way the app and later tickets consume it.
@Suite struct FakeUsageProviderBehavior {
    @Test func returnsTheCannedSnapshotUnderItsProviderID() async throws {
        let canned = UsageSnapshot(
            provider: ProviderID("fake"),
            fetchedAt: Date(timeIntervalSince1970: 1_000),
            windows: [UsageWindow(id: "session", kind: .fiveHour, title: "5-hour", percentUsed: 42, resetsAt: nil)]
        )
        let provider: any UsageProvider = FakeUsageProvider(snapshot: canned)

        #expect(provider.id == ProviderID("fake"))
        #expect(try await provider.fetchUsage() == canned)
    }

    // Only a lower bound is asserted: an upper bound would flake on a loaded machine.
    @Test func waitsAtLeastTheConfiguredDelayBeforeAnswering() async throws {
        let provider = FakeUsageProvider(snapshot: .sample(fetchedAt: Date(timeIntervalSince1970: 0)), delay: .milliseconds(200))

        let elapsed = try await ContinuousClock().measure { _ = try await provider.fetchUsage() }

        #expect(elapsed >= .milliseconds(200))
    }

    // The sample stands in for real data, so it must drive the badge like a real snapshot would.
    @Test func sampleSnapshotHasABadgeWindow() {
        let sample = UsageSnapshot.sample(fetchedAt: Date(timeIntervalSince1970: 0))

        #expect(sample.primaryWindow?.kind == .fiveHour)
    }
}
