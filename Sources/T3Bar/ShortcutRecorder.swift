import T3BarCore
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A field that records a global shortcut: click it, press the combination. Escape cancels; Delete on its own
/// removes the shortcut, as does the clear button beside it. While recording it shows the modifiers being held, so a
/// Hyper key visibly registers as ✦ before any letter is pressed.
struct ShortcutRecorder: View {
    let shortcut: GlobalShortcut?
    let onChange: (GlobalShortcut?) -> Void
    /// Lets the app stand its current shortcut down while a new one is typed.
    let onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var heldModifiers: GlobalShortcut.Modifiers = []
    @State private var rejection: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Button(action: toggleRecording) {
                    Text(label)
                        .monospacedDigit()
                        .frame(minWidth: 96)
                        .foregroundStyle(isRecording || shortcut == nil ? .secondary : .primary)
                }
                .accessibilityLabel(accessibilityLabel)
                .help(isRecording ? "Press the shortcut, or Escape to cancel" : "Click to record a shortcut")
                if shortcut != nil, !isRecording {
                    Button { onChange(nil) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove shortcut")
                    .help("Remove shortcut")
                }
            }
            if let rejection {
                Text(rejection)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stopRecording()
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording {
            return heldModifiers.isEmpty ? "Type shortcut…" : heldModifiers.symbols
        }
        return shortcut?.displayName ?? "Record Shortcut"
    }

    private var accessibilityLabel: String {
        if isRecording { return "Recording shortcut" }
        return shortcut.map { "Shortcut \($0.spokenName)" } ?? "Record shortcut"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        rejection = nil
        heldModifiers = []
        onRecordingChange(true)
        // Swallows every key while recording, so the combination reaches neither the button nor the window.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        heldModifiers = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onRecordingChange(false)
    }

    private func handle(_ event: NSEvent) {
        let modifiers = GlobalShortcut.Modifiers(event.modifierFlags)
        if event.type == .flagsChanged {
            heldModifiers = modifiers
            return
        }
        switch (Int(event.keyCode), modifiers.isEmpty) {
        case (kVK_Escape, true):
            rejection = nil
            stopRecording()
        case (kVK_Delete, true), (kVK_ForwardDelete, true):
            rejection = nil
            onChange(nil)
            stopRecording()
        default:
            let typed = GlobalShortcut(keyCode: event.keyCode, modifiers: modifiers)
            guard typed.isUsable else {
                rejection = "Include ⌃ or ⌘, or use a function key."
                return
            }
            rejection = nil
            onChange(typed)
            stopRecording()
        }
    }
}

extension GlobalShortcut.Modifiers {
    /// Caps Lock, Fn and the like are dropped: they are not part of a shortcut, and a Hyper key sends exactly the four.
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}

extension GlobalShortcut {
    /// As menus show it, e.g. "✦K" or "⌃⌘Space".
    var displayName: String {
        modifiers.symbols + keyName
    }

    /// E.g. "Hyper K", "Control Command Space".
    var spokenName: String {
        (modifiers.spokenNames + [keyName]).joined(separator: " ")
    }

    /// Keys with a conventional name or glyph use it; any other key shows the character it types on the current
    /// layout, so a recorded Y reads as Z on a German keyboard, matching the key cap.
    private var keyName: String {
        if let number = functionKeyNumber { return "F\(number)" }
        if let special = Self.specialKeyNames[Int(keyCode)] { return special }
        return characterOnCurrentLayout(keyCode: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
}

/// What the key types with no modifiers held; nil when the layout has no character for it.
private func characterOnCurrentLayout(keyCode: UInt16) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    return data.withUnsafeBytes { bytes -> String? in
        guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count,
                                    &length, &characters)
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
