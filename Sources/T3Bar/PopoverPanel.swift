import AppKit
import SwiftUI

/// The popover's window, in place of `NSPopover`: hung just below the menu bar with no arrow, on the same glass as
/// the system's own menu bar extras (Sound, Wi-Fi), so T3 Bar reads as part of the menu bar rather than an app
/// pointing at it.
///
/// It closes the way a menu does: on a click anywhere outside it, on Escape, or when the app loses focus.
@MainActor
final class PopoverPanel: NSPanel {
    var onClose: () -> Void = {}

    private let hostingController: NSHostingController<GlassSurface<AnyView>>
    private var sizeObservation: NSKeyValueObservation?
    private var outsideClickMonitor: Any?
    private var closedAt = Date.distantPast
    /// Where the window's top edge hangs; it grows and shrinks downward from it as its content changes.
    private var anchorTop: CGFloat = 0

    /// Matches the system's menu bar extras, whose corners are rounder than a menu's.
    nonisolated static let cornerRadius: CGFloat = 16
    /// The gap the system leaves between the menu bar and a menu bar extra's window.
    private static let gapBelowMenuBar: CGFloat = 3
    /// Keeps the glass off the screen edge when the item sits near it.
    private static let screenMargin: CGFloat = 8

    init(content: some View) {
        hostingController = NSHostingController(rootView: GlassSurface(content: AnyView(content)))
        hostingController.sizingOptions = .preferredContentSize
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own shadow, shaped to its corners; the window's would follow the square frame.
        hasShadow = false
        level = .popUpMenu
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        contentView = hostingController.view
        followContentSize()
    }

    // A borderless window refuses key status by default, which would leave Escape and ⌘, with nowhere to go.
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    override func close() {
        guard isVisible else { return }
        stopWatchingOutsideClicks()
        super.close()
        closedAt = Date()
        onClose()
    }

    /// Keeps the top edge fixed whatever size AppKit asks for, so content changes never lift the panel off the
    /// menu bar.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        frame.origin.y = anchorTop - frame.height
        super.setFrame(frame, display: flag)
    }

    /// A click on the menu bar item closes the panel as the mouse goes down, since the panel loses focus, and would
    /// open it again as the mouse comes up. The item asks this first, so that click only closes, as it does for a
    /// menu.
    var wasJustClosed: Bool {
        Date().timeIntervalSince(closedAt) < 0.3
    }

    /// Opens under `button`, aligned to its left edge like a menu, and shifted left if it would run off screen.
    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window, let screen = buttonWindow.screen else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = hostingController.view.fittingSize
        let room = GlassSurface<AnyView>.shadowRoom
        let visible = screen.visibleFrame
        let glassX = min(max(buttonFrame.minX, visible.minX + Self.screenMargin),
                         visible.maxX - (size.width - 2 * room) - Self.screenMargin)
        anchorTop = min(buttonFrame.minY, visible.maxY) - Self.gapBelowMenuBar + room
        setFrame(NSRect(origin: NSPoint(x: glassX - room, y: 0), size: size), display: false)
        // An accessory app is not active by default; without activating, the panel could not become key.
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        watchOutsideClicks()
    }

    /// Resizes with the content, e.g. from an error message to the window rows.
    private func followContentSize() {
        sizeObservation = hostingController.observe(\.preferredContentSize) { [weak self] controller, _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.setContentSize(controller.preferredContentSize)
            }
        }
    }

    /// Clicks in other apps, the desktop or another menu bar item never reach this app, so they are watched for
    /// globally. Clicks on T3 Bar's own item are left to the item, which toggles the panel.
    private func watchOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func stopWatchingOutsideClicks() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}

/// Liquid Glass on macOS 26 and later; the thick material before it.
struct GlassSurface<Content: View>: View {
    let content: Content

    /// Transparent space round the glass for the shadow it draws, which the window edge would otherwise clip into
    /// a faint square behind the round corners.
    static var shadowRoom: CGFloat { 24 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PopoverPanel.cornerRadius, style: .continuous)
        Group {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content
                    .background(.regularMaterial, in: shape)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            }
        }
        .padding(Self.shadowRoom)
    }
}
