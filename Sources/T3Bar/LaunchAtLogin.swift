import ServiceManagement

/// The login item is the system's state, not a preference: it is read back from `SMAppService` every time so the
/// toggle also reflects changes made in System Settings > Login Items.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Throws when the system refuses, e.g. under `swift run`, where there is no app bundle to register.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
