import Testing
@testable import T3BarCore

// Method: key codes are written as literals from Carbon's Events.h (kVK_ANSI_K = 40, kVK_F13 = 105), so the tests
// do not share a table with the code under test.
@Suite struct GlobalShortcutSymbols {
    @Test func hyperIsOneGlyph() {
        #expect(GlobalShortcut.Modifiers.hyper.symbols == "✦")
        #expect(GlobalShortcut.Modifiers.hyper.spokenNames == ["Hyper"])
    }

    // Built in reverse, so the check is on the listing order rather than insertion order.
    @Test func otherCombinationsListInMenuOrder() {
        let modifiers: GlobalShortcut.Modifiers = [.command, .shift, .control]
        #expect(modifiers.symbols == "⌃⇧⌘")
        #expect(modifiers.spokenNames == ["Control", "Shift", "Command"])
    }

    @Test func threeOfTheFourIsNotHyper() {
        #expect(GlobalShortcut.Modifiers([.control, .option, .command]).symbols == "⌃⌥⌘")
    }
}

@Suite struct GlobalShortcutUsability {
    @Test(arguments: [
        GlobalShortcut.Modifiers.hyper, [.command], [.control], [.option, .command], [.shift, .control],
    ])
    func acceptsControlOrCommand(modifiers: GlobalShortcut.Modifiers) {
        #expect(GlobalShortcut(keyCode: 40, modifiers: modifiers).isUsable)
    }

    // Plain typing, or combinations macOS 15 refuses to deliver.
    @Test(arguments: [GlobalShortcut.Modifiers(), [.shift], [.option], [.option, .shift]])
    func rejectsKeysThatTypeOrThatMacOSRefuses(modifiers: GlobalShortcut.Modifiers) {
        #expect(!GlobalShortcut(keyCode: 40, modifiers: modifiers).isUsable)
    }

    @Test func functionKeyWorksAlone() {
        let f13 = GlobalShortcut(keyCode: 105, modifiers: [])
        #expect(f13.isUsable)
        #expect(f13.functionKeyNumber == 13)
    }
}
