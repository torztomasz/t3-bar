import T3BarCore
import AppKit
import SwiftUI

/// Owns the menu bar item: draws the badge and tooltip, toggles the usage popover on left click,
/// and reports right click (or control-click) as a refresh request.
@MainActor
final class StatusItemController: NSObject {
    var onRefreshRequested: () -> Void = {}

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover: PopoverPanel
    private let settingsStore: SettingsStore
    private var shownStates: [ProviderState] = []
    private var tooltipClock: Timer?
    private lazy var refreshTracer = PillTracer(button: statusItem.button)

    init(popoverContent: some View, settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        popover = PopoverPanel(content: popoverContent)
        super.init()
        configureButton()
        markItemDeselectedWhenPopoverCloses()
        startTooltipClock()
        refitBadgeWhenDisplaysChange()
        render()
    }

    /// Shows one reading per state in the badge, in the order given.
    func show(_ states: [ProviderState]) {
        shownStates = states
        render()
        refreshTracer.follow(isRefreshing: states.contains(where: \.isRefreshing))
    }

    func settingsDidChange() {
        render()
    }

    /// Makes way for the Settings window, which the popover would otherwise cover.
    func closePopover() {
        popover.close()
    }

    /// For the global shortcut, which has no button press of its own to anchor to.
    func togglePopover() {
        guard let button = statusItem.button else { return }
        togglePopover(from: button)
    }

    /// Badge and tooltip both describe, for each provider, the window chosen for it in settings.
    private func render() {
        let inMenuBar = settingsStore.settings.menuBarProviders(among: shownStates.map { ($0.id, $0.defaultPlacement) })
        let readings = shownStates.filter { inMenuBar.contains($0.id) }.map { state in
            BadgeReading(state: state, window: state.badgeWindow(for: settingsStore.settings.badgeWindowIDs[state.id]))
        }
        let height = BadgeSize.height(menuBarHeights: NSScreen.screens.map(\.menuBarHeight))
        let rows = readings.map { BadgeRenderer.Row(mark: ProviderMark.image(forDriver: $0.state.driver, named: $0.state.displayName),
                                                        text: $0.text) }
        statusItem.button?.image = rows.isEmpty
            ? BadgeRenderer.placeholder(height: height)
            : BadgeRenderer.image(rows: rows, height: height)
        refreshTracer.fit(around: BadgeLayout(rowCount: rows.count, height: height))
        statusItem.button?.toolTip = readings.isEmpty
            ? UsageText.emptyBadge
            : readings.map { $0.tooltip(now: Date()) }.joined(separator: "\n")
    }

    /// The tooltip counts down to the reset in minutes, but data only changes every poll, so it is redrawn on
    /// its own to stay accurate in between.
    private func startTooltipClock() {
        tooltipClock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    /// The badge's height depends on the menu bars it appears in, which change as displays come and go.
    private func refitBadgeWhenDisplaysChange() {
        // The notification center keeps the observer for the app's lifetime, which is this controller's lifetime.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func markItemDeselectedWhenPopoverCloses() {
        popover.onClose = { [weak self] in
            guard let self else { return }
            statusItem.markDeselected(presenting: popover)
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if isSecondaryClick(NSApp.currentEvent) {
            onRefreshRequested()
        } else {
            togglePopover(from: sender)
        }
    }

    // Control-click counts as right click, matching the macOS convention for one-button input.
    private func isSecondaryClick(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isVisible {
            popover.close()
        } else if !popover.wasJustClosed {
            statusItem.markSelected(presenting: popover) { [weak self] in self?.popover.close() }
            popover.show(below: button)
        }
    }
}

/// One provider's part of the badge: the window chosen for it and what the badge and tooltip say about it.
private struct BadgeReading {
    let state: ProviderState
    let window: UsageWindow?

    var text: String {
        UsageText.badge(window: window, hasError: state.lastError != nil)
    }

    func tooltip(now: Date) -> String {
        UsageText.tooltip(providerName: state.displayName, window: window,
                          forecast: window.flatMap { state.forecasts[$0.id] },
                          errorDescription: state.lastError?.localizedDescription, now: now)
    }
}

/// Runs a light around the badge's capsule while a refresh runs, so a right-click refresh is acknowledged where the
/// user clicked (see `RefreshTracer` for how it moves and settles). Under Reduce Motion the outline brightens and
/// fades in place instead, so the refresh still shows without movement.
@MainActor
private final class PillTracer: NSObject {
    private weak var button: NSStatusBarButton?
    private let light = CAShapeLayer()
    private var tracer = RefreshTracer()
    private var isRefreshing = false
    private var displayLink: CADisplayLink?
    private var lightsOut: Timer?
    /// The outline the path was last built for, so it is only rebuilt when the badge changes shape.
    private var drawnOutline: Outline?

    private struct Outline: Equatable {
        let rect: CGRect
        let cornerRadius: CGFloat
    }

    /// Thin enough to leave the reading legible at 24 pt.
    private static let lineWidthPerPointOfHeight: CGFloat = 0.08
    private static let minimumLineWidth: CGFloat = 1.5
    /// A soft halo, so the light reads as a glow rather than a drawn line.
    private static let haloOpacity: Float = 0.5

    init(button: NSStatusBarButton?) {
        self.button = button
        super.init()
        button?.wantsLayer = true
        light.fillColor = nil
        light.lineCap = .round
        light.shadowOffset = .zero
        light.shadowOpacity = Self.haloOpacity
        light.isHidden = true
        button?.layer?.addSublayer(light)
    }

    /// Reacts only to a change, since every state update passes through here.
    func follow(isRefreshing refreshing: Bool) {
        guard refreshing != isRefreshing else { return }
        isRefreshing = refreshing
        let now = Date()
        if refreshing {
            tracer.start(at: now)
            lightsOut?.invalidate()
            restartDisplayLink()
        } else {
            tracer.stop(at: now)
            scheduleLightsOut()
        }
        draw(at: now)
    }

    /// Called after every badge redraw: the outline widens and narrows with its text, and the light takes the
    /// menu bar's text colour, so it matches the reading.
    func fit(around layout: BadgeLayout) {
        guard let button, let cell = button.cell else { return }
        let image = cell.imageRect(forBounds: button.bounds)
        let outline = layout.isStacked ? box(around: image, in: button.bounds)
                                       : capsule(around: image, in: button.bounds)
        let rect = outline.rect
        let color = button.effectiveAppearance.resolved(.labelColor)
        withoutImplicitAnimation {
            light.strokeColor = color
            light.shadowColor = color
            guard outline != drawnOutline else { return }
            drawnOutline = outline
            let lineWidth = max(rect.height * Self.lineWidthPerPointOfHeight, Self.minimumLineWidth)
            light.frame = rect
            light.lineWidth = lineWidth
            light.shadowRadius = lineWidth * 0.6
            light.path = doubledOutline(of: CGRect(origin: .zero, size: rect.size).insetBy(dx: lineWidth / 2,
                                                                                           dy: lineWidth / 2),
                                        cornerRadius: outline.cornerRadius - lineWidth / 2,
                                        topAtMinY: button.isFlipped)
        }
    }

    /// The image is only as wide as its text, so a capsule that tight would run through the digits; the button's own
    /// spacing either side gives the light room to pass round them.
    private func capsule(around image: CGRect, in bounds: CGRect) -> Outline {
        Outline(rect: CGRect(x: bounds.minX, y: image.minY, width: bounds.width, height: image.height),
                cornerRadius: image.height / 2)
    }

    /// Stacked readings fill the image's corners, which a capsule's round ends would run through. Corners no wider
    /// than the button's spacing turn before they reach the image, and the button's full height gives the light
    /// the room above and below that a short menu bar's image does not have.
    private func box(around image: CGRect, in bounds: CGRect) -> Outline {
        Outline(rect: bounds, cornerRadius: min(image.minX - bounds.minX, bounds.height / 2))
    }

    /// Linked to the button's display, so the light moves in step with the screen it is on, including while a
    /// menu is being tracked. It only runs while there is light to draw. Every refresh gets a new one, because a
    /// link that stopped firing while its display slept may never fire again.
    private func restartDisplayLink() {
        stopDisplayLink()
        guard let button else { return }
        let link = button.displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = Date()
        draw(at: now)
        if !tracer.isMoving(at: now) {
            stopDisplayLink()
        }
    }

    /// The display link alone would leave the light hanging mid-lap if it stopped firing, e.g. while the display
    /// slept through a refresh.
    private func scheduleLightsOut() {
        lightsOut?.invalidate()
        guard let goesOutAt = tracer.goesOutAt else { return }
        let timer = Timer(fire: goesOutAt, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.draw(at: Date())
                self.stopDisplayLink()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        lightsOut = timer
    }

    private func draw(at now: Date) {
        withoutImplicitAnimation {
            guard let segment = tracer.segment(at: now) else {
                light.isHidden = true
                return
            }
            light.isHidden = false
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                glowInPlace(segment)
            } else {
                let stroke = segment.strokeOnDoubledOutline
                light.opacity = 1
                light.strokeStart = stroke.lowerBound
                light.strokeEnd = stroke.upperBound
            }
        }
    }

    /// The whole outline, pulsing once per lap. The pulse is dark at the starting point, where the head stops, so
    /// it ends there as smoothly as the moving light drains away.
    private func glowInPlace(_ segment: RefreshTracer.Segment) {
        let pulse = 0.5 - 0.5 * cos(2 * .pi * segment.head)
        light.opacity = Float(0.7 * pulse)
        light.strokeStart = 0
        light.strokeEnd = 0.5
    }

    /// The light is a sublayer, which Core Animation would otherwise ease into every new position a quarter second
    /// late.
    private func withoutImplicitAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}

/// The rounded outline twice over, clockwise from the middle of its top edge, so the light sets off and settles
/// at the top, where the eye expects a loop to begin. Built from corner tangents, which trace the same way on
/// screen whether or not the button's coordinates are flipped.
private func doubledOutline(of rect: CGRect, cornerRadius: CGFloat, topAtMinY: Bool) -> CGPath {
    let top = topAtMinY ? rect.minY : rect.maxY
    let bottom = topAtMinY ? rect.maxY : rect.minY
    let radius = min(cornerRadius, rect.height / 2, rect.width / 2)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.midX, y: top))
    for _ in 0..<2 {
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX, y: bottom),
                    radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom), tangent2End: CGPoint(x: rect.minX, y: bottom),
                    radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom), tangent2End: CGPoint(x: rect.minX, y: top),
                    radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.midX, y: top),
                    radius: radius)
        path.addLine(to: CGPoint(x: rect.midX, y: top))
    }
    return path
}

extension NSAppearance {
    /// A dynamic colour as it looks in this appearance, for layers, which do not follow appearance changes.
    fileprivate func resolved(_ color: NSColor) -> CGColor {
        var resolved = color.cgColor
        performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }
}

/// The menu bar draws a selected item with a capsule behind it for as long as its menu or window is open. On macOS 26
/// the capsule follows only what the item reports as presented, which AppKit does for `NSMenu` and `NSPopover`
/// but offers no public way to do for a window of our own; the button's highlight, the public route, no longer
/// draws anything there. So the panel is reported through the same private calls `NSPopover` makes, and the
/// highlight is kept for systems without them.
@MainActor
extension NSStatusItem {
    private static let willPresent = Selector(("_willPresentContent:cancellationHandler:"))
    /// Despite its name, `NSPopover` calls this as it closes, and it is what ends the selection.
    private static let didPresent = Selector(("_didPresentContent:"))

    /// `onCancel` runs when the menu bar ends the selection itself, e.g. as the user moves to another item.
    fileprivate func markSelected(presenting content: NSWindow, onCancel: @escaping @MainActor @Sendable () -> Void) {
        guard responds(to: Self.willPresent) else {
            DispatchQueue.main.async { self.button?.highlight(true) }
            return
        }
        typealias WillPresent = @convention(c) (NSStatusItem, Selector, NSWindow, AnyObject) -> Void
        let cancel: @convention(block) () -> Void = { Task { @MainActor in onCancel() } }
        unsafeBitCast(method(for: Self.willPresent), to: WillPresent.self)(self, Self.willPresent, content,
                                                                           cancel as AnyObject)
    }

    fileprivate func markDeselected(presenting content: NSWindow) {
        guard responds(to: Self.didPresent) else {
            button?.highlight(false)
            return
        }
        typealias DidPresent = @convention(c) (NSStatusItem, Selector, NSWindow) -> Void
        unsafeBitCast(method(for: Self.didPresent), to: DidPresent.self)(self, Self.didPresent, content)
    }
}

extension NSScreen {
    /// Points between the top of the screen and its visible area; 0 while a full-screen app hides the menu bar.
    fileprivate var menuBarHeight: Double {
        Double(frame.maxY - visibleFrame.maxY)
    }
}
