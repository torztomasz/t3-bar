import Foundation

/// Forecasts every window of a snapshot from that window's own history, so the 5-hour and the weekly limits each
/// get a pace of their own. Histories live one file per (provider, window) under `directory`, so a restart resumes
/// every forecast where it left off.
///
/// Main-actor bound because it caches stores in a plain dictionary; the app forecasts after each poll on the main
/// actor anyway.
@MainActor
public final class WindowForecaster {
    public let directory: URL
    /// Opened on first use, keyed by file so a window keeps one store for the app's lifetime.
    private var stores: [URL: SampleStore] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    /// Keeps history in `~/Library/Application Support/AI Bar`; the directory is created on first save.
    public static func inApplicationSupport() -> WindowForecaster {
        WindowForecaster(directory: URL.applicationSupportDirectory
            .appending(path: "AI Bar", directoryHint: .isDirectory))
    }

    /// Records each window's reading at the snapshot's fetch time, then forecasts it with that reading included.
    /// A window of unknown length is left out: without a start there is no anchor to project from.
    public func forecasts(for snapshot: UsageSnapshot) -> [UsageWindow.ID: DrainForecast] {
        var forecasts: [UsageWindow.ID: DrainForecast] = [:]
        for window in snapshot.windows {
            guard let length = window.kind.length else { continue }
            let store = store(for: window, of: snapshot.provider, length: length)
            store.record(window, at: snapshot.fetchedAt)
            forecasts[window.id] = DrainEstimator(windowLength: length)
                .forecast(for: window, samples: store.samples(), now: snapshot.fetchedAt)
        }
        return forecasts
    }

    /// `samples-<provider>-<window>.json`, both ids made file-safe. `length` is the window kind's, already known
    /// to exist, passed in so it is not unwrapped a second time.
    private func store(for window: UsageWindow, of provider: ProviderID, length: TimeInterval) -> SampleStore {
        let fileURL = file(named: "samples-\(fileSafe(provider.rawValue))-\(fileSafe(window.id)).json")
        if let store = stores[fileURL] { return store }
        let store = SampleStore(fileURL: fileURL, windowLength: length)
        stores[fileURL] = store
        return store
    }

    private func file(named name: String) -> URL {
        directory.appending(path: name, directoryHint: .notDirectory)
    }
}

/// Window ids contain `:` and `·`. Encoding rather than replacing them keeps distinct ids in distinct files, and
/// encoding `-` keeps the separator between provider and window unambiguous.
private func fileSafe(_ id: String) -> String {
    id.utf8.map { byte in
        isFileSafe(byte) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
    }.joined()
}

private func isFileSafe(_ byte: UInt8) -> Bool {
    switch UnicodeScalar(byte) {
    case "a"..."z", "A"..."Z", "0"..."9", "_": true
    default: false
    }
}
