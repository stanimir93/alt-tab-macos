import Cocoa
import ShortcutRecorder

// Stub so SwitcherSession.swift's Preview-frame cache compiles in the test target. The real enum
// lives in LightImageView.swift (not in the test target); the session only stores and returns
// values, so mirroring the cases without the helper methods is enough.
enum CALayerContents {
    case cgImage(CGImage?)
    case pixelBuffer(CVPixelBuffer?)
}

enum SearchKeyResult {
    case handled
    case passToField
    case passToShortcuts
}

class TilesViewMock {
    var isSearchEditing = false
    func handleSearchEditingKeyDown(_ event: NSEvent) -> SearchKeyResult { return .passToField }
}

class TilesPanelMock {
    var tilesView = TilesViewMock()
    var isKeyWindow = false
}

class App {
    class AppMock {
        var tilesPanel = TilesPanelMock()
    }
    static let app = AppMock()
    static let bundleIdentifier = "com.lwouis.alt-tab-macos"
}

class TilesPanel {
    static let shared = TilesPanel()
    var isKeyWindow: Bool {
        get { App.app.tilesPanel.isKeyWindow }
        set { App.app.tilesPanel.isKeyWindow = newValue }
    }
}

class TilesView {
    static var isSearchEditing: Bool {
        get { App.app.tilesPanel.tilesView.isSearchEditing }
        set { App.app.tilesPanel.tilesView.isSearchEditing = newValue }
    }

    static func handleSearchEditingKeyDown(_ event: NSEvent) -> SearchKeyResult {
        return App.app.tilesPanel.tilesView.handleSearchEditingKeyDown(event)
    }

    static func giveTheFieldTheCaretNow() {}
}

class ControlsTab {
    // Fidelity gaps vs production — tests relying on this registry inherit them, so override
    // entries explicitly when they matter (two conflict-detector bugs hid behind them already):
    // 1. every hold is the same ⌥, so a conflict that should be found via a shortcut's OWN hold
    //    is accidentally also found via the other holds (production defaults share this shape;
    //    use a unique hold like ⌃ to isolate same-index detection);
    // 2. nextWindowShortcut/nextWindowShortcut2 are stored RAW (⇥, `) while production stores
    //    them COMBINED with their hold (⌥⇥, ⌥`).
    static let defaultShortcuts = [
        "holdShortcut": ATShortcut(Shortcut(keyEquivalent: "⌥")!, "holdShortcut", .global, .up, 0),
        "holdShortcut2": ATShortcut(Shortcut(keyEquivalent: "⌥")!, "holdShortcut2", .global, .up, 1),
        "holdShortcut3": ATShortcut(Shortcut(keyEquivalent: "⌥")!, "holdShortcut3", .global, .up, 2),
        "nextWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "⇥")!, "nextWindowShortcut", .global, .down),
        "nextWindowShortcut2": ATShortcut(Shortcut(keyEquivalent: "`")!, "nextWindowShortcut2", .global, .down),
        "→": ATShortcut(Shortcut(keyEquivalent: "→")!, "→", .local, .down),
        "←": ATShortcut(Shortcut(keyEquivalent: "←")!, "←", .local, .down),
        "↑": ATShortcut(Shortcut(keyEquivalent: "↑")!, "↑", .local, .down),
        "↓": ATShortcut(Shortcut(keyEquivalent: "↓")!, "↓", .local, .down),
//        "vimCycleRight": ATShortcut(Shortcut(keyEquivalent: "l")!, "vimCycleRight", .local, .down),
//        "vimCycleLeft": ATShortcut(Shortcut(keyEquivalent: "h")!, "vimCycleLeft", .local, .down),
//        "vimCycleUp": ATShortcut(Shortcut(keyEquivalent: "k")!, "vimCycleUp", .local, .down),
//        "vimCycleDown": ATShortcut(Shortcut(keyEquivalent: "j")!, "vimCycleDown", .local, .down),
        "focusWindowShortcut": ATShortcut(Shortcut(keyEquivalent: " ")!, "focusWindowShortcut", .local, .down),
        "previousWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "⇧")!, "previousWindowShortcut", .local, .down),
        "cancelShortcut": ATShortcut(Shortcut(keyEquivalent: "⎋")!, "cancelShortcut", .local, .down),
        "searchShortcut": ATShortcut(Shortcut(keyEquivalent: "s")!, "searchShortcut", .local, .down),
        "closeWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "w")!, "closeWindowShortcut", .local, .down),
        "minDeminWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "m")!, "minDeminWindowShortcut", .local, .down),
        "toggleFullscreenWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "f")!, "toggleFullscreenWindowShortcut", .local, .down),
        "quitAppShortcut": ATShortcut(Shortcut(keyEquivalent: "q")!, "quitAppShortcut", .local, .down),
        "hideShowAppShortcut": ATShortcut(Shortcut(keyEquivalent: "h")!, "hideShowAppShortcut", .local, .down),
    ]
    static var shortcuts = defaultShortcuts

    static func executeAction(_ action: String) {
        shortcutsActionsTriggered.append(action)
        if action.starts(with: "holdShortcut") {
            SwitcherSession.current = nil
        }
        if action.starts(with: "nextWindowShortcut") {
            let session = SwitcherSession.current ?? {
                let new = SwitcherSession()
                SwitcherSession.current = new
                return new
            }()
            session.shortcutIndex = Preferences.nameToIndex(action)
        }
    }

    static var shortcutsActionsTriggered: [String] = []
}

enum ShortcutActions {
    static func execute(_ id: String) {
        ControlsTab.executeAction(id)
    }
}

class KeyRepeatTimer {
    static func stopTimerForRepeatingKey(_ shortcutName: String) {
    }
}

class Logger {
    static func debug(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {}
    static func info(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {}
    static func warning(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {}
    static func error(_ message: @escaping () -> Any?, file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {}
}

class Preferences {
    static var shortcutStyle: ShortcutStylePreference = .focusOnRelease
    static var holdShortcut = ["⌥", "⌥", "⌥"]
    static let minShortcutCount = 1
    static let maxShortcutCount = 9
    // Matches `defaultShortcuts` (3 hold slots: holdShortcut / holdShortcut2 / holdShortcut3).
    static var shortcutCount = 3

    static func indexToName(_ baseName: String, _ index: Int) -> String {
        return baseName + (index == 0 ? "" : String(index + 1))
    }

    static func nameToIndex(_ name: String) -> Int {
        guard let number = name.last?.wholeNumberValue else { return 0 }
        return number - 1
    }

    static func effectiveShortcutStyle(_ index: Int) -> ShortcutStylePreference {
        return shortcutStyle
    }
}

enum ShortcutStylePreference: CaseIterable {
    case focusOnRelease
    case doNothingOnRelease
    case searchOnRelease
}

class ModifierFlags {
    static var current: NSEvent.ModifierFlags = []
}

/// Scratch `UserDefaults` suite for tests.
///
/// `removePersistentDomain` clears a suite's keys but never unlinks its plist,
/// so a suite named after a fresh UUID leaves one empty 42-byte file in
/// ~/Library/Preferences per test, per run. That is how a dev machine ended up
/// with 62k of them. Reuse one fixed suite name per test class and delete the
/// file on the way out. Safe because the Test scheme sets parallelizable = NO.
enum TestDefaults {
    static func make(_ suiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    static func tearDown(_ defaults: UserDefaults, _ suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeSuite(named: suiteName)
        let plist = NSHomeDirectory() + "/Library/Preferences/\(suiteName).plist"
        try? FileManager.default.removeItem(atPath: plist)
    }
}
