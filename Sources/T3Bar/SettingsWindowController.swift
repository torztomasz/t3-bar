import AppKit
import SwiftUI

/// Owns the one Settings window. It is kept rather than released on close, so reopening shows the same window
/// where the user left it.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(content: some View) {
        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = .preferredContentSize
        window = NSWindow(contentViewController: hostingController)
        window.title = "T3 Bar Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    /// An accessory app is never frontmost on its own, so without activating the window would open behind
    /// whatever the user was working in.
    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
