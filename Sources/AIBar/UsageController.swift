import AIBarCore
import AppKit

/// Owns the usage data: polls every provider, forecasts every window's drain from its recorded readings, and
/// publishes the result for the badge and the popover.
@MainActor
final class UsageController: ObservableObject {
    /// One entry per provider the user has turned on, in the order the badge and the popover list them.
    @Published private(set) var states: [ProviderState] = [] {
        didSet { onStatesChanged(states) }
    }

    /// For AppKit consumers (the status item) that cannot observe SwiftUI state.
    var onStatesChanged: ([ProviderState]) -> Void = { _ in }

    /// Every provider the app knows, turned on or not. Worked out again on each refresh, since T3 Code can start
    /// reporting a provider at any time.
    @Published private(set) var providers: [any UsageProvider]
    private let discoverProviders: @MainActor () -> [any UsageProvider]
    private let settingsStore: SettingsStore
    private let forecaster = WindowForecaster.inApplicationSupport()
    private var pollingTask: Task<Void, Never>?
    /// The interval `pollingTask` sleeps for, to tell a changed interval from any other settings change.
    private var pollingInterval: Duration?

    init(discoverProviders: @escaping @MainActor () -> [any UsageProvider], settingsStore: SettingsStore) {
        self.discoverProviders = discoverProviders
        self.settingsStore = settingsStore
        providers = discoverProviders()
        states = statesOfFetchedProviders()
    }

    /// The stalest provider's refresh time, since a single "Updated … ago" vouches for all the data shown;
    /// nil while any provider has never refreshed.
    var oldestRefresh: Date? {
        let refreshes = states.map(\.lastRefreshedAt)
        return refreshes.contains(nil) ? nil : refreshes.compactMap { $0 }.min()
    }

    var isRefreshing: Bool {
        states.contains(where: \.isRefreshing)
    }

    /// True while any provider's latest fetch failed, whose data is then out of date.
    var hasFailedRefresh: Bool {
        states.contains { $0.lastError != nil }
    }

    /// Refreshes now and every refresh interval after, and again on wake because a sleeping Mac misses polls and
    /// the reading it last showed may be hours old. Calling it again does nothing.
    func start() {
        guard pollingTask == nil else { return }
        Task { await refresh() }
        startPolling()
        // The notification center keeps the observer for the app's lifetime, which is this controller's lifetime.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// A new interval starts counting from now instead of after the old one runs out, so going from 15 minutes to 1
    /// takes effect within a minute.
    func settingsDidChange() {
        showEnabledProviders()
        guard pollingTask != nil, settingsStore.settings.refreshInterval != pollingInterval else { return }
        startPolling()
    }

    /// Fetches every provider concurrently. A provider still busy with an earlier refresh is skipped rather than
    /// asked twice. A failed fetch keeps the previous snapshot, so the badge shows the last known reading.
    func refresh() async {
        Log.app.notice("refreshing usage")
        rediscoverProviders()
        let due = Set(states.filter { !$0.isRefreshing }.map(\.id))
        // Marked on a copy so observers redraw once, not once per provider.
        var marked = states
        for index in marked.indices where due.contains(marked[index].id) {
            marked[index].isRefreshing = true
        }
        states = marked
        await withTaskGroup(of: (ProviderID, Result<UsageSnapshot, any Error>).self) { group in
            for provider in providers where due.contains(provider.id) {
                group.addTask { (provider.id, await fetchResult(from: provider)) }
            }
            for await (id, result) in group {
                apply(result, to: id)
            }
        }
    }

    /// A provider turned off takes its data with it; one turned on is fetched at once rather than at the next poll.
    private func showEnabledProviders() {
        let fetched = statesOfFetchedProviders()
        guard fetched.map(\.id) != states.map(\.id) else { return }
        let hasNewProvider = fetched.contains { provider in !states.contains { $0.id == provider.id } }
        states = fetched
        if hasNewProvider && pollingTask != nil {
            Task { await refresh() }
        }
    }

    /// Called at the start of a refresh, which then fetches whatever provider this adds.
    private func rediscoverProviders() {
        let discovered = discoverProviders()
        guard discovered.map(\.id) != providers.map(\.id) else { return }
        providers = discovered
        states = statesOfFetchedProviders()
    }

    /// One per provider that is not off, keeping what is already known about each.
    private func statesOfFetchedProviders() -> [ProviderState] {
        providers.filter { settingsStore.settings.placement(of: $0.id, defaultingTo: $0.defaultPlacement).isFetched }
            .map { provider in states.first { $0.id == provider.id } ?? ProviderState(provider: provider) }
    }

    /// Each refresh runs in a task of its own, so replacing the loop cancels only its sleep, never a fetch in flight.
    private func startPolling() {
        pollingTask?.cancel()
        let interval = settingsStore.settings.refreshInterval
        pollingInterval = interval
        Log.app.notice("refreshing usage every \(interval.wholeMinutes) min")
        pollingTask = Task { [weak self] in
            // Sleep only throws on cancellation, i.e. when a restart has already started this loop's replacement.
            while (try? await Task.sleep(for: interval)) != nil {
                Task { await self?.refresh() }
            }
        }
    }

    private func apply(_ result: Result<UsageSnapshot, any Error>, to id: ProviderID) {
        // Gone when the provider was turned off while its fetch was under way.
        guard let index = states.firstIndex(where: { $0.id == id }) else { return }
        var state = states[index]
        state.isRefreshing = false
        switch result {
        case .success(let snapshot):
            state.snapshot = snapshot
            state.forecasts = forecaster.forecasts(for: snapshot)
            state.lastError = nil
        case .failure(let error):
            state.lastError = error
            Log.app.error("""
                fetching \(state.id.rawValue, privacy: .public) usage failed: \
                \(error.localizedDescription, privacy: .public)
                """)
        }
        // One assignment so observers see a single, consistent change.
        states[index] = state
    }
}

/// What the app knows about one provider after its latest refresh.
struct ProviderState: Identifiable {
    let id: ProviderID
    let displayName: String
    let defaultPlacement: ProviderPlacement
    /// The last successful fetch; kept through failures.
    var snapshot: UsageSnapshot?
    /// For the windows of `snapshot`; a window of unknown length has none.
    var forecasts: [UsageWindow.ID: DrainForecast] = [:]
    /// Cleared by the next successful fetch.
    var lastError: (any Error)?
    var isRefreshing = false

    init(provider: any UsageProvider) {
        id = provider.id
        displayName = provider.displayName
        defaultPlacement = provider.defaultPlacement
    }

    func placement(in settings: AppSettings) -> ProviderPlacement {
        settings.placement(of: id, defaultingTo: defaultPlacement)
    }

    /// Derived rather than stored so it can never disagree with the snapshot it describes.
    var lastRefreshedAt: Date? { snapshot?.fetchedAt }

    /// The window the badge shows for the user's choice `id` (see `UsageSnapshot.window(for:)`); nil before the
    /// first reading.
    func badgeWindow(for id: String?) -> UsageWindow? {
        snapshot?.window(for: id)
    }
}

private func fetchResult(from provider: any UsageProvider) async -> Result<UsageSnapshot, any Error> {
    do {
        return .success(try await provider.fetchUsage())
    } catch {
        return .failure(error)
    }
}
