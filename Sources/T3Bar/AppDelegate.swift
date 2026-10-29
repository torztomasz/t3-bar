import T3BarCore
import AppKit
import os

/// Composes the app: the usage controller feeds the status item's badge and popover, and both refresh triggers
/// (right click, the popover's button) go back to the controller. The global shortcut, when set, toggles the popover.
/// Settings changes reach the poller and the badge as soon as they are made.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore(defaults: .standard)
    private let hubs = T3CodeHubs()
    private lazy var usage = UsageController(discoverProviders: { [hubs] in UsageProviders.all(hubs: hubs) },
                                             settingsStore: settingsStore)
    private lazy var hotKey = PopoverHotKey(settingsStore: settingsStore)
    private lazy var settingsWindow = SettingsWindowController(
        content: SettingsView(settingsStore: settingsStore, usage: usage, hotKey: hotKey))
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let popover = UsagePopoverView(controller: usage, onOpenSettings: { [weak self] in
            self?.openSettings()
        }, onQuit: {
            NSApplication.shared.terminate(nil)
        })
        let statusItem = StatusItemController(popoverContent: popover, settingsStore: settingsStore)
        statusItem.onRefreshRequested = { [weak usage] in
            Task { await usage?.refresh() }
        }
        usage.onStatesChanged = { [weak statusItem] states in
            statusItem?.show(states)
        }
        hotKey.onPress = { [weak statusItem] in
            statusItem?.togglePopover()
        }
        settingsStore.onChange = { [weak usage, weak statusItem, weak hotKey] _ in
            usage?.settingsDidChange()
            statusItem?.settingsDidChange()
            hotKey?.settingsDidChange()
        }
        statusItemController = statusItem
        usage.start()
        // Hub readings arrive as T3 Code takes them, so they are shown then rather than at the next poll.
        hubs.start { [weak usage] in
            Task { @MainActor in await usage?.refresh() }
        }
    }

    private func openSettings() {
        statusItemController?.closePopover()
        settingsWindow.show()
    }
}

enum Log {
    static let app = Logger(subsystem: "com.torz.t3bar", category: "app")
}
