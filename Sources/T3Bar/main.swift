import AppKit

// `.accessory` keeps the Dock icon hidden under `swift run` too, where the bundle's LSUIElement does not apply.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
