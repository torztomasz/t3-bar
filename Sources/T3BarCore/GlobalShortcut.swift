/// A key combination that works from any app. Stored as a hardware key code rather than a character, so it stays on
/// the same physical key whatever keyboard layout is active.
public struct GlobalShortcut: Equatable, Sendable {
    /// A virtual key code, as in Carbon's `kVK_*` constants.
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A bare key would swallow ordinary typing, and since macOS 15 the system silently refuses global shortcuts whose
    /// only modifiers are ⌥ and ⇧, so those could be set but would never fire. Function keys are safe alone.
    public var isUsable: Bool {
        !modifiers.isDisjoint(with: [.control, .command]) || functionKeyNumber != nil
    }

    /// 1 for F1 and so on; nil for any other key.
    public var functionKeyNumber: Int? {
        Self.functionKeyCodes.firstIndex(of: keyCode).map { $0 + 1 }
    }

    /// F1 to F20, in order. The codes follow the physical keys, not their numbers.
    private static let functionKeyCodes: [UInt16] = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// All four at once: what a Hyper key sends, usually Caps Lock remapped by Karabiner-Elements or Raycast.
        public static let hyper: Modifiers = [.control, .option, .shift, .command]
    }
}

extension GlobalShortcut.Modifiers {
    /// In the order macOS menus list them. Hyper shows as ✦, the glyph Raycast and others give it, because four
    /// symbols in a row read as noise rather than as the single key the user pressed.
    public var symbols: String {
        self == .hyper ? "✦" : Self.named.filter { contains($0.modifier) }.map(\.symbol).joined()
    }

    /// For VoiceOver, which reads ✦ and ⌃ as "black four pointed star" and "up arrowhead".
    public var spokenNames: [String] {
        self == .hyper ? ["Hyper"] : Self.named.filter { contains($0.modifier) }.map(\.spokenName)
    }

    /// The words the settings file uses, so a stored shortcut stays readable with `defaults read`.
    public var storedNames: [String] {
        Self.named.filter { contains($0.modifier) }.map(\.storedName)
    }

    /// Nil when any name is unknown, so a hand-edited or future value is dropped rather than half-applied.
    public init?(storedNames: [String]) {
        var modifiers: Self = []
        for name in storedNames {
            guard let named = Self.named.first(where: { $0.storedName == name }) else { return nil }
            modifiers.insert(named.modifier)
        }
        self = modifiers
    }

    private static let named: [(modifier: Self, symbol: String, spokenName: String, storedName: String)] = [
        (.control, "⌃", "Control", "control"),
        (.option, "⌥", "Option", "option"),
        (.shift, "⇧", "Shift", "shift"),
        (.command, "⌘", "Command", "command"),
    ]
}
