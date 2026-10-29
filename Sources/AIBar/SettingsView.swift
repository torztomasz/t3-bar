import AIBarCore
import SwiftUI

/// The Settings window's content. Every control writes straight through to `SettingsStore`, so a change applies
/// the moment it is made, the way macOS settings do; there is no Save button.
struct SettingsView: View {
    let settingsStore: SettingsStore
    /// For the providers on offer and the titles of the windows the badge can show.
    @ObservedObject var usage: UsageController
    /// Only to report a shortcut the system refused, and to stand it down while a new one is recorded.
    let hotKey: PopoverHotKey

    /// Mirrors the system's login item rather than a stored preference; re-read whenever the window appears.
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    launchAtLoginToggle
                    refreshIntervalPicker
                    openShortcutRecorder
                }
                Section("Providers") {
                    ForEach(usage.providers, id: \.id) { provider in
                        placementPicker(for: provider)
                    }
                }
            }
            .formStyle(.grouped)
            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchesAtLogin = LaunchAtLogin.isEnabled }
    }

    private var launchAtLoginToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            // A closure rather than the method itself, which crashes the Swift 6.2 compiler as a binding's setter.
            Toggle("Launch at login", isOn: Binding(get: { launchesAtLogin }, set: { setLaunchesAtLogin($0) }))
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var refreshIntervalPicker: some View {
        Picker("Refresh every", selection: Binding(
            get: { settingsStore.settings.refreshInterval },
            set: { interval in settingsStore.update { $0.refreshInterval = interval } }
        )) {
            ForEach(AppSettings.refreshIntervalChoices, id: \.self) { interval in
                Text(minutesLabel(interval)).tag(interval)
            }
        }
    }

    /// One choice per provider covers both where it appears and which window the menu bar shows, since a window is
    /// only chosen for the menu bar.
    ///
    /// Lists what the badge would actually show: a stored window the snapshot no longer reports is displayed as the
    /// primary window it falls back to. Until the provider has reported, only the default can be named.
    private func placementPicker(for provider: any UsageProvider) -> some View {
        let settings = settingsStore.settings
        let state = usage.states.first { $0.id == provider.id }
        let windows = state?.snapshot?.windows ?? []
        let shownWindowID = state?.badgeWindow(for: settings.badgeWindowIDs[provider.id])?.id
        return Picker(provider.displayName, selection: Binding(
            get: { ProviderChoice(placement: settings.placement(of: provider.id, defaultingTo: provider.defaultPlacement),
                                  windowID: shownWindowID) },
            set: { choice in settingsStore.update { choice.apply(to: &$0, for: provider.id) } }
        )) {
            Section("Menu bar and popover") {
                if windows.isEmpty {
                    Text("5-hour").tag(ProviderChoice.menuBar(windowID: shownWindowID))
                }
                ForEach(windows) { window in
                    Text(window.title).tag(ProviderChoice.menuBar(windowID: window.id))
                }
            }
            Divider()
            Text("Popover only").tag(ProviderChoice.popoverOnly)
            Text("Off").tag(ProviderChoice.off)
        }
    }

    private var openShortcutRecorder: some View {
        LabeledContent {
            ShortcutRecorder(
                shortcut: settingsStore.settings.openPopoverShortcut,
                onChange: { shortcut in settingsStore.update { $0.openPopoverShortcut = shortcut } },
                onRecordingChange: hotKey.setPaused)
        } label: {
            Text("Open AI Bar")
            if let failure = hotKey.failure {
                Text(failure)
            }
        }
    }

    /// Reads the outcome back from the system instead of trusting the request, so a refused change leaves the toggle
    /// where it was.
    private func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            let action = enabled ? "add AI Bar to" : "remove AI Bar from"
            launchAtLoginError = "Couldn't \(action) login items: \(error.localizedDescription)"
        }
        launchesAtLogin = LaunchAtLogin.isEnabled
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// A provider's row in Settings: its placement, together with the window the menu bar shows.
private enum ProviderChoice: Hashable {
    /// Nil is the provider's primary window.
    case menuBar(windowID: UsageWindow.ID?)
    case popoverOnly
    case off

    init(placement: ProviderPlacement, windowID: UsageWindow.ID?) {
        switch placement {
        case .menuBar: self = .menuBar(windowID: windowID)
        case .popoverOnly: self = .popoverOnly
        case .off: self = .off
        }
    }

    /// Leaving the menu bar keeps the window chosen for it, so it is back when the provider returns.
    func apply(to settings: inout AppSettings, for provider: ProviderID) {
        switch self {
        case .menuBar(let windowID):
            settings.badgeWindowIDs[provider] = windowID
            settings.place(provider, .menuBar)
        case .popoverOnly:
            settings.place(provider, .popoverOnly)
        case .off:
            settings.place(provider, .off)
        }
    }
}

private func minutesLabel(_ interval: Duration) -> String {
    interval.wholeMinutes == 1 ? "1 minute" : "\(interval.wholeMinutes) minutes"
}
