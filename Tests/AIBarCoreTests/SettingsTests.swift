import Foundation
import Testing
@testable import AIBarCore

// Method: compare against the defaults the ticket specifies, written out as literals.
@Suite struct AppSettingsDefaults {
    @Test func pollsEveryFiveMinutesShowsEveryProvidersPrimaryWindowAndHasNoShortcut() {
        #expect(AppSettings() == AppSettings(refreshInterval: .seconds(5 * 60), badgeWindowIDs: [:],
                                             providerPlacements: [:],
                                             openPopoverShortcut: nil))
    }

    // A provider the settings have never heard of is one added by an update or found in T3 Code; it starts out
    // wherever it asks to.
    @Test(arguments: [ProviderPlacement.menuBar, .popoverOnly])
    func everyProviderStartsOutWhereItDoesByDefault(_ defaultPlacement: ProviderPlacement) {
        #expect(AppSettings().placement(of: ProviderID("added-later"), defaultingTo: defaultPlacement)
                == defaultPlacement)
    }
}

// Method: place providers through `place`, the call the Settings window makes, and read the outcome back through
// `placement(of:)`, the question the poller and the badge ask.
@Suite struct ProviderPlacements {
    @Test func placingOneProviderLeavesTheOthersInTheMenuBar() {
        var settings = AppSettings()

        settings.place(chatGPT, .popoverOnly)

        #expect(settings.placement(of: chatGPT, defaultingTo: .menuBar) == .popoverOnly)
        #expect(settings.placement(of: claude, defaultingTo: .menuBar) == .menuBar)
    }

    // The poller skips a provider that is off; one left to the popover still needs its data.
    @Test func onlyAProviderThatIsOffIsNotFetched() {
        #expect(ProviderPlacement.menuBar.isFetched)
        #expect(ProviderPlacement.popoverOnly.isFetched)
        #expect(!ProviderPlacement.off.isFetched)
    }

    // A T3 Code provider starts in the popover, so the menu bar has to be remembered as a choice of its own.
    @Test func aChoiceThatMatchesAnotherProvidersDefaultStillOverridesItsOwn() {
        var settings = AppSettings()

        settings.place(antigravity, .menuBar)

        #expect(settings.placement(of: antigravity, defaultingTo: .popoverOnly) == .menuBar)
    }
}

// Method: place providers through `place` and ask which the badge shows, listing them in the app's provider order:
// T3 Code's built-in Claude and Codex, then the rest.
@Suite struct MenuBarCapacity {
    @Test func theBadgeShowsEveryProviderPlacedThereWhileTheyFit() {
        var settings = AppSettings()
        settings.place(chatGPT, .popoverOnly)
        settings.place(antigravity, .menuBar)

        #expect(settings.menuBarProviders(among: appProviders) == [claude, antigravity])
    }

    // E.g. Antigravity was placed in the menu bar, dropped out of T3 Code while Claude and Codex filled it, and
    // came back.
    @Test func aProviderPlacedThereAfterItFilledUpIsLeftOut() {
        var settings = AppSettings()
        settings.place(antigravity, .menuBar)

        #expect(settings.menuBarProviders(among: appProviders) == [claude, chatGPT])
    }

    @Test func aProviderThatIsOffTakesNoPlace() {
        var settings = AppSettings()
        settings.place(chatGPT, .off)

        #expect(settings.menuBarProviders(among: appProviders) == [claude])
    }

    // Settings shows the provider left out as Popover only, so freeing a place must not bring it back unasked.
    @Test func makingRoomDoesNotBringBackAProviderShownInThePopover() {
        var settings = AppSettings()
        settings.place(antigravity, .menuBar)

        settings.moveMenuBarOverflowToPopover(among: appProviders)
        settings.place(chatGPT, .popoverOnly)

        #expect(settings.menuBarProviders(among: appProviders) == [claude])
        #expect(settings.placement(of: antigravity, defaultingTo: .popoverOnly) == .popoverOnly)
    }

    @Test func nothingPlacedThereLeavesItEmpty() {
        var settings = AppSettings()
        for (provider, _) in appProviders {
            settings.place(provider, .popoverOnly)
        }

        #expect(settings.menuBarProviders(among: appProviders).isEmpty)
    }
}

// Method: every test gets its own `UserDefaults` suite, removed afterwards, so nothing leaks into the real app's
// preferences or between tests. "Survives a relaunch" is checked by opening a second store on the same suite.
@MainActor @Suite struct SettingsPersistence {
    @Test func freshPreferencesGiveTheDefaults() {
        withIsolatedDefaults { defaults in
            #expect(SettingsStore(defaults: defaults).settings == AppSettings())
        }
    }

    @Test func changesSurviveARelaunch() {
        withIsolatedDefaults { defaults in
            SettingsStore(defaults: defaults).update {
                $0.refreshInterval = .seconds(10 * 60)
                $0.badgeWindowIDs = [claude: "weekly_all", chatGPT: "weekly"]
                $0.place(chatGPT, .off)
                $0.place(claude, .popoverOnly)
            }

            #expect(SettingsStore(defaults: defaults).settings
                    == AppSettings(refreshInterval: .seconds(10 * 60),
                                   badgeWindowIDs: [claude: "weekly_all", chatGPT: "weekly"],
                                   providerPlacements: [chatGPT: .off, claude: .popoverOnly]))
        }
    }

    @Test func returningAProviderToTheMenuBarSurvivesARelaunch() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.update { $0.place(chatGPT, .off) }
            store.update { $0.place(chatGPT, .menuBar) }

            #expect(SettingsStore(defaults: defaults).settings.placement(of: chatGPT, defaultingTo: .popoverOnly)
                    == .menuBar)
        }
    }

    // Going back to the primary window must stick too, not resurrect the previously chosen one.
    @Test func clearingTheBadgeWindowSurvivesARelaunch() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.update { $0.badgeWindowIDs[claude] = "weekly_all" }
            store.update { $0.badgeWindowIDs[claude] = nil }

            #expect(SettingsStore(defaults: defaults).settings.badgeWindowIDs.isEmpty)
        }
    }

    @Test func shortcutSurvivesARelaunch() {
        withIsolatedDefaults { defaults in
            let hyperK = GlobalShortcut(keyCode: 40, modifiers: .hyper)
            SettingsStore(defaults: defaults).update { $0.openPopoverShortcut = hyperK }

            #expect(SettingsStore(defaults: defaults).settings.openPopoverShortcut == hyperK)
        }
    }

    @Test func removingTheShortcutSurvivesARelaunch() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.update { $0.openPopoverShortcut = GlobalShortcut(keyCode: 40, modifiers: .hyper) }
            store.update { $0.openPopoverShortcut = nil }

            #expect(SettingsStore(defaults: defaults).settings.openPopoverShortcut == nil)
        }
    }

    @Test func reportsEachChange() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            var reported: [AppSettings] = []
            store.onChange = { reported.append($0) }

            store.update { $0.refreshInterval = .seconds(60) }

            #expect(reported == [AppSettings(refreshInterval: .seconds(60))])
        }
    }
}

// Method: write raw values under the store's keys, as a hand edit with `defaults write` or another app version would,
// then open a store and check it reads the defaults instead of the junk.
@MainActor @Suite struct SettingsFromBadStoredValues {
    // `Int.max` minutes would overflow if converted to a duration before being checked.
    @Test(arguments: [7, 0, -5, 600, Int.max, "ten", 2.5] as [any Sendable])
    func intervalNotOnOfferFallsBackToFiveMinutes(stored: any Sendable) {
        withIsolatedDefaults { defaults in
            defaults.set(stored, forKey: SettingsStore.Key.refreshIntervalMinutes)

            #expect(SettingsStore(defaults: defaults).settings.refreshInterval == .seconds(5 * 60))
        }
    }

    @Test(arguments: ["weekly_all", 42, ["claudeAgent": 42]] as [any Sendable])
    func unreadableBadgeWindowsFallBackToThePrimaryWindows(stored: any Sendable) {
        withIsolatedDefaults { defaults in
            defaults.set(stored, forKey: SettingsStore.Key.badgeWindowIDs)

            #expect(SettingsStore(defaults: defaults).settings.badgeWindowIDs.isEmpty)
        }
    }

    @Test(arguments: ["off", 42, ["codex": 42], ["codex": "sidebar"]] as [any Sendable])
    func unreadablePlacementsLeaveEveryProviderInTheMenuBar(stored: any Sendable) {
        withIsolatedDefaults { defaults in
            defaults.set(stored, forKey: SettingsStore.Key.providerPlacements)

            #expect(SettingsStore(defaults: defaults).settings == AppSettings())
        }
    }

    // One entry from a future version must not cost the entries this version understands.
    @Test func anUnknownPlacementDoesNotHideTheKnownOnes() {
        withIsolatedDefaults { defaults in
            defaults.set(["codex": "sidebar", "claudeAgent": "off"], forKey: SettingsStore.Key.providerPlacements)

            #expect(SettingsStore(defaults: defaults).settings == AppSettings(providerPlacements: [claude: .off]))
        }
    }

    @Test(arguments: [
        "hyper-k",
        ["keyCode": 40] as [String: any Sendable],
        ["keyCode": 40, "modifiers": ["command", "fn"]] as [String: any Sendable],
        ["keyCode": 70_000, "modifiers": ["command"]] as [String: any Sendable],
        ["keyCode": -1, "modifiers": ["command"]] as [String: any Sendable],
        ["keyCode": 40, "modifiers": ["option"]] as [String: any Sendable],
    ] as [any Sendable])
    func unreadableOrUnusableShortcutFallsBackToNone(stored: any Sendable) {
        withIsolatedDefaults { defaults in
            defaults.set(stored, forKey: SettingsStore.Key.openPopoverShortcut)

            #expect(SettingsStore(defaults: defaults).settings.openPopoverShortcut == nil)
        }
    }

    @Test func updatingToAnUnusableShortcutKeepsNone() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.update { $0.openPopoverShortcut = GlobalShortcut(keyCode: 40, modifiers: []) }

            #expect(store.settings.openPopoverShortcut == nil)
        }
    }

    // Keeps the running app and the next launch in agreement: an interval that would be discarded on relaunch is
    // discarded now.
    @Test func updatingToAnIntervalNotOnOfferKeepsTheDefault() {
        withIsolatedDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.update { $0.refreshInterval = .seconds(7) }

            #expect(store.settings.refreshInterval == .seconds(5 * 60))
        }
    }
}

private let claude = ProviderID("claudeAgent")
private let antigravity = ProviderID("antigravity")
private let appProviders: [(id: ProviderID, defaultPlacement: ProviderPlacement)] = [
    (claude, .menuBar), (chatGPT, .menuBar), (antigravity, .popoverOnly),
]
private let chatGPT = ProviderID("codex")

@MainActor private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
    let suiteName = "AIBarCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    body(defaults)
}
