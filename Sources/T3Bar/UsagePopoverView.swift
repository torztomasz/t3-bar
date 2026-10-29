import T3BarCore
import SwiftUI

/// Popover shown on left click, laid out like the system's own menu bar extras: every provider's windows with reset
/// times and forecasts, each provider its own section, then menu rows to refresh, open Settings or quit.
///
/// Motion is brief and only marks a change of state: the refresh icon turns while data is on its way and confirms
/// its arrival, and values that change settle into place. With Reduce Motion on, movement is dropped and only
/// opacity fades remain.
struct UsagePopoverView: View {
    @ObservedObject var controller: UsageController
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    /// About the width of the system's Sound and Wi-Fi windows.
    private static let width: CGFloat = 300

    var body: some View {
        // Re-evaluated periodically so "resets in", "Updated … ago" and the time cursors keep moving while the
        // popover is open.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(controller.states) { state in
                    if state.id != controller.states.first?.id { MenuSeparator() }
                    ProviderSection(state: state, now: context.date)
                        .padding(.horizontal, MenuMetrics.contentInset)
                        .padding(.vertical, 8)
                }
                if controller.states.isEmpty {
                    Text(controller.providers.isEmpty ? UsageText.noT3Code : UsageText.noProviders)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MenuMetrics.contentInset)
                        .padding(.vertical, 8)
                }
                MenuSeparator()
                actions(now: context.date)
            }
            .padding(.vertical, 6)
            .frame(width: Self.width)
        }
    }

    private func actions(now: Date) -> some View {
        VStack(spacing: 0) {
            RefreshRow(isRefreshing: controller.isRefreshing, hasFailed: controller.hasFailedRefresh,
                       updated: UsageText.updated(controller.oldestRefresh, now: now)) {
                Task { await controller.refresh() }
            }
            // ⌘, is the standard Settings shortcut; an accessory app has no menu bar to carry it, so the row does.
            Button(action: onOpenSettings) {
                MenuRowLabel(title: "Settings…", trailing: "⌘,") { Image(systemName: "gearshape") }
            }
            .buttonStyle(MenuRowStyle())
            .keyboardShortcut(",", modifiers: .command)
            Button(action: onQuit) {
                MenuRowLabel(title: "Quit T3 Bar", trailing: "⌘Q") { Image(systemName: "power") }
            }
            .buttonStyle(MenuRowStyle())
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

/// The system menu's spacing, so the popover's edges line up the way a menu bar extra's do.
private enum MenuMetrics {
    /// From the glass edge to text.
    static let contentInset: CGFloat = 14
    /// From the glass edge to a row's highlight; text inside it still lines up with `contentInset`.
    static let rowInset: CGFloat = 5
    /// Concentric with the panel's corners at `rowInset`.
    static let rowCornerRadius = PopoverPanel.cornerRadius - rowInset
}

/// A hairline between sections, inset from the glass edges as a menu's separators are.
private struct MenuSeparator: View {
    var body: some View {
        Divider()
            .padding(.horizontal, MenuMetrics.contentInset - 4)
            .padding(.vertical, 5)
    }
}

/// A menu item's look: highlighted under the pointer, and a little more while pressed, to show it is live.
private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }

    private struct MenuRow: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, MenuMetrics.contentInset - MenuMetrics.rowInset)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(highlight, in: RoundedRectangle(cornerRadius: MenuMetrics.rowCornerRadius,
                                                            style: .continuous))
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .padding(.horizontal, MenuMetrics.rowInset)
        }

        private var highlight: Color {
            if configuration.isPressed { return .primary.opacity(0.16) }
            return isHovered ? .primary.opacity(0.1) : .clear
        }
    }
}

/// Icon, title, and a secondary note on the right, e.g. the row's shortcut.
private struct MenuRowLabel<Icon: View>: View {
    let title: String
    let trailing: String
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: 8) {
            icon
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
            Spacer(minLength: 12)
            Text(trailing)
                .foregroundStyle(.secondary)
        }
    }
}

/// One provider: its name with the badge window's reset countdown, then its windows. An error with no data to fall
/// back on takes the rows' place; with an older snapshot it is shown above the rows, which are still the best
/// information available.
private struct ProviderSection: View {
    let state: ProviderState
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.displayName).font(.headline.weight(.bold))
            if let error = state.lastError {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { window in
                    WindowRow(window: window, forecast: state.forecasts[window.id], now: now)
                }
            } else if state.lastError == nil {
                LoadingRows()
            }
        }
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let forecast: DrainForecast?
    let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                Spacer()
                Text(UsageText.percent(window.percentUsed))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: window.percentUsed))
                    .animation(.smooth(duration: 0.3), value: window.percentUsed)
            }
            UsageBarView(bar: UsageBar(window: window, forecast: forecast, now: now))
            // A long reset countdown next to a lockout may not fit on one row; the lockout then goes on its own line
            // instead of wrapping mid-duration.
            ViewThatFits(in: .horizontal) {
                HStack {
                    resetsLine
                    Spacer()
                    lockoutLine
                }
                VStack(alignment: .leading, spacing: 2) {
                    resetsLine
                    lockoutLine
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var resetsLine: some View {
        Text(UsageText.resetsIn(window.resetsAt, now: now)).fixedSize()
    }

    @ViewBuilder private var lockoutLine: some View {
        if let forecast {
            Text(UsageText.lockout(forecast, resetsAt: window.resetsAt, now: now))
                .fontWeight(isLockedOut ? .semibold : nil)
                .foregroundStyle(isLockedOut ? AnyShapeStyle(UsageLevel.critical.color) : AnyShapeStyle(.secondary))
                .fixedSize()
        }
    }

    /// Being locked out is the one thing the row must not let the user miss, so it takes the bar's critical colour.
    /// That includes a drained window with no reset time: its line still says "Locked out" and the badge is red.
    private var isLockedOut: Bool {
        if case .willDrain = forecast?.outlook { true } else { false }
    }
}

/// Stands in for window rows until the first reading arrives, in their shape, so the popover does not jump when the
/// data lands. Static rather than shimmering: loading takes about a second and needs no attention drawn to it.
private struct LoadingRows: View {
    /// Claude reports three windows, so the placeholder has the height of the rows it stands in for.
    private static let rowCount = 3

    var body: some View {
        ForEach(0..<Self.rowCount, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly · Model")
                Capsule().fill(.quaternary).frame(height: UsageBarView.height)
                Text("resets in 0h 00m").font(.caption)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading usage")
    }
}

/// Drawn by hand rather than with `ProgressView`, which turns grey whenever the popover is not the key window and so
/// would hide the threshold colour exactly when the user glances at it.
private struct UsageBarView: View {
    let bar: UsageBar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 8
    /// Faint enough that the solid fill stays the obvious reading, visible enough to notice where usage is heading.
    private static let estimateOpacity = 0.25
    private static let cursorWidth: CGFloat = 1.5
    /// Present on fills of every colour and on the empty track, without competing with the fill for attention.
    private static let cursorOpacity = 0.45

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let estimate = bar.estimate {
                    Capsule()
                        .fill(estimate.level.color.opacity(Self.estimateOpacity))
                        .frame(width: geometry.size.width * estimate.fraction)
                }
                Capsule()
                    .fill(bar.fill.level.color)
                    .frame(width: geometry.size.width * bar.fill.fraction)
                if let elapsed = bar.elapsedFraction {
                    timeCursor(at: elapsed, barWidth: geometry.size.width)
                }
            }
        }
        .frame(height: Self.height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: bar)
    }

    /// The only mark on the bar that is not a fill, so it reads as "now" against the usage: a fill reaching past it
    /// is usage outpacing time. Kept inside the bar at either end rather than half cut off.
    private func timeCursor(at fraction: Double, barWidth: CGFloat) -> some View {
        let travel = max(barWidth - Self.cursorWidth, 0)
        return Capsule()
            .fill(.primary.opacity(Self.cursorOpacity))
            .frame(width: Self.cursorWidth)
            .offset(x: travel * fraction)
    }
}

/// Refreshes every provider and says when the data is from. Its icon turns while a refresh runs and settles upright
/// when it ends (see `RefreshSpin`), then briefly turns into a checkmark if the refresh succeeded, so the user learns
/// it worked without reading the timestamp. A failure gets no checkmark: its message already shows above. With Reduce
/// Motion on the icon stays still and dims instead of turning, and the checkmark fades in and out rather than morphing.
private struct RefreshRow: View {
    let isRefreshing: Bool
    let hasFailed: Bool
    let updated: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = RefreshSpin()
    @State private var showsCheck = false
    /// Counts successful refreshes, so each starts its own confirmation and cancels a previous one still showing.
    @State private var confirmations = 0

    /// Deep, because this icon is already secondary: a shallow dim would not register.
    private static let dimmedOpacity = 0.4
    /// Long enough to register at a glance, short enough not to be mistaken for a state.
    private static let checkHold: Duration = .seconds(1)
    /// A gentle spring for the checkmark's arrival; bounce is kept low, as it is only confirming.
    private static let checkArrival = Animation.spring(duration: 0.3, bounce: 0.2)
    /// Faster than the arrival: by then the checkmark is only getting out of the way.
    private static let checkDeparture = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)

    var body: some View {
        Button(action: action) {
            MenuRowLabel(title: "Refresh", trailing: updated) { icon }
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: updated)
        }
        .buttonStyle(MenuRowStyle())
        .onChange(of: isRefreshing, initial: true) { followRefreshing() }
        .onChange(of: isRefreshing) { wasRefreshing, refreshing in
            if refreshing {
                showsCheck = false
            } else if wasRefreshing && !hasFailed {
                confirmations += 1
            }
        }
        // Turning Reduce Motion on mid-refresh stops the spin; the dim takes over.
        .onChange(of: reduceMotion) { followRefreshing() }
        .task(id: spin) {
            // The timeline only re-reads `paused` when the view updates, so end the settle once it is over.
            guard (try? await Task.sleep(for: .seconds(RefreshSpin.settleDuration))) != nil else { return }
            spin.finishSettling(at: .now)
        }
        .task(id: confirmations) {
            guard confirmations > 0 else { return }
            await confirm()
        }
    }

    private var icon: some View {
        TimelineView(.animation(paused: !spin.isMoving(at: .now))) { context in
            Image(systemName: showsCheck ? "checkmark" : "arrow.clockwise")
                .foregroundStyle(showsCheck ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.downUp))
                .rotationEffect(.degrees(spin.degrees(at: context.date)))
        }
        // Scoped to the opacity, so the fade can never animate anything else in the row.
        .animation(.easeOut(duration: 0.15)) {
            $0.opacity(reduceMotion && isRefreshing ? Self.dimmedOpacity : 1)
        }
    }

    private func followRefreshing() {
        if isRefreshing && !reduceMotion {
            spin.start(at: .now)
        } else {
            spin.stop(at: .now)
        }
    }

    /// Waits for the spin to land upright first, so the checkmark never appears tilted.
    private func confirm() async {
        guard (try? await Task.sleep(for: .seconds(RefreshSpin.settleDuration))) != nil else { return }
        withAnimation(Self.checkArrival) { showsCheck = true }
        guard (try? await Task.sleep(for: Self.checkHold)) != nil else { return }
        withAnimation(Self.checkDeparture) { showsCheck = false }
    }
}

extension UsageLevel {
    fileprivate var color: Color {
        switch self {
        case .ok: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}
