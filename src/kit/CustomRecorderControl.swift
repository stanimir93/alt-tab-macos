import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class CustomRecorderControl: RecorderControl {
    static let allowedModifiers = NSEvent.ModifierFlags(arrayLiteral: [.command, .control, .option, .shift])
    var clearable: Bool!
    /// The preference key this recorder edits. Derived from `identifier` so it can never drift out of
    /// sync with the key the write path (`persist`) and the conflict detector key off.
    var id: String { identifier!.rawValue }

    convenience init(_ shortcut: Shortcut?, _ clearable: Bool, _ id: String) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.clearable = clearable
        identifier = NSUserInterfaceItemIdentifier(id)
        delegate = self
        allowsEscapeToCancelRecording = false
        allowsDeleteToClearShortcutAndEndRecording = false
        allowsModifierFlagsOnlyShortcut = true
        restrictModifiers([])
        objectValue = shortcut
        addOrUpdateConstraint(widthAnchor, 100)
    }

    override func drawClearButton(_ aDirtyRect: NSRect) {
        if clearable {
            super.drawClearButton(aDirtyRect)
        }
    }

    override func clearAndEndRecording() {
        if clearable {
            super.clearAndEndRecording()
        }
    }

    // macOS 26 (Tahoe) stopped swallowing exceptions thrown during AppKit's constraint-update
    // pass: it now routes them through `+[NSApplication _crashOnException:]`, turning a thrown
    // NSException into a hard SIGTRAP. `RecorderControl`'s `updateActiveConstraints` /
    // `updateLabelConstraints` can throw when the control is laid out before it's in a window
    // (e.g. a `fittingSize` measurement while building the Settings window): the alignment guide's
    // frame isn't resolved yet, so `updateLabelConstraints`
    // can compute a non-finite label width, and `-[NSLayoutConstraint setConstant:]` rejects NaN
    // with an NSException. We catch it here, one frame below AppKit's crash-on-exception wrapper,
    // so the worst case is a momentarily mis-sized label instead of a crash. Both calls still
    // return normally, so `RecorderControl.updateConstraints` reaches its `[super updateConstraints]`
    // and the pass completes (no relayout loop). Seen via applicationShouldHandleReopen building
    // the Settings window's shortcut recorders.
    override func updateActiveConstraints() {
        ObjCExceptionCatcher.catching { super.updateActiveConstraints() }
    }

    override func updateLabelConstraints() {
        ObjCExceptionCatcher.catching { super.updateLabelConstraints() }
    }

    func restrictModifiers(_ restrictedModifiers: NSEvent.ModifierFlags) {
        set(allowedModifierFlags: CustomRecorderControl.allowedModifiers.subtracting(restrictedModifiers), requiredModifierFlags: [], allowsEmptyModifierFlags: true)
    }

    /// How to clear the conflicting shortcut when the user picks "Unassign and continue". Resolved
    /// from the id alone — arrow/vim keys are turned off through their preference; everything else is
    /// cleared through `Preferences` by id (so a shortcut that isn't on screen is handled correctly). The
    /// human-readable label shown in the dialog comes separately from `ControlsTab.conflictLabel`.
    private enum ShortcutConflict {
        case arrow
        case vim
        case regular(id: String)

        static func classify(_ id: String) -> ShortcutConflict {
            if ["←", "→", "↑", "↓"].contains(id) { return .arrow }
            if id.starts(with: "vimCycle") { return .vim }
            return .regular(id: id)
        }
    }

    func alertIfSameShortcutAlreadyAssigned(_ candidateShortcut: Shortcut, _ shortcutAlreadyAssigned: String) -> Bool {
        let conflict = ShortcutConflict.classify(shortcutAlreadyAssigned)
        // `conflictLabel` returns nil only for an id with no known action, which can't happen for a
        // real detected conflict.
        let label = ControlsTab.conflictLabel(shortcutAlreadyAssigned) ?? "an unknown action"
        // Always offer to resolve it, including when editing a Hold: unassigning a conflicting Trigger
        // clears its "and press" part (the hold itself is never the thing unassigned).
        let informativeText = String(format: NSLocalizedString("Shortcut already assigned to: %@", comment: ""),
                                     ControlsTab.nonBreaking(label))
        guard ControlsTab.confirmUnassigningConflict(informativeText, in: window) else { return false }
        switch conflict {
        case .arrow:
            Preferences.set("arrowKeysEnabled", "false")
        case .vim:
            Preferences.set("vimKeysEnabled", "false")
        case .regular(let conflictingId):
            ControlsTab.unassignShortcut(conflictingId)
        }
        updateShortcut(self, candidateShortcut, self, id)
        return true
    }

    func updateShortcut(_ control: CustomRecorderControl, _ objectValue: Shortcut?, _ senderControl: CustomRecorderControl, _ id: String) {
        control.objectValue = objectValue
        senderControl.persist()
        ControlsTab.shortcutChangedCallback(senderControl)
    }

    func alertIfShortcutReservedByMacos(_ candidateShortcut: Shortcut, _ shortcutReservedByMacos: String) -> Bool {
        let label = ControlsTab.conflictLabel(shortcutReservedByMacos) ?? "an unknown action"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("macOS reserves ⌘⌥⎋, ⌘⌥⇧⎋, and ⌘⌥⇧⌃⎋ for Force Quit and they cannot be unbound. AltTab cannot use them.\n\nYour change would assign one of these to: %@.", comment: ""), label)
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: ""))
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityFocused(true)
        let userChoice = alert.runAttached(to: window)
        guard userChoice == .alertFirstButtonReturn, id != shortcutReservedByMacos else { return false }
        ControlsTab.unassignShortcut(shortcutReservedByMacos)
        updateShortcut(self, candidateShortcut, self, id)
        return true
    }

    /// Writes the displayed shortcut to the preference `id`, unless it is already stored.
    func persist() {
        let oldValue = Preferences.shortcut(id)
        if oldValue == nil && objectValue == nil { return }
        if let oldValue, let objectValue, oldValue.isEqual(objectValue) { return }
        Preferences.setShortcut(id, objectValue, stringRepresentation: stringValue)
    }
}

extension CustomRecorderControl: RecorderControlDelegate {
    func recorderControl(_ control: RecorderControl, canRecord shortcut: Shortcut) -> Bool {
        switch CustomRecorderControlTestable.isShortcutAcceptable(id, shortcut) {
        case .accepted: persist()
        case .modifiersOnlyButContainsKeycode: return false
        case .conflictWithExistingShortcut(let s): return alertIfSameShortcutAlreadyAssigned(shortcut, s)
        case .reservedByMacos(let s): return alertIfShortcutReservedByMacos(shortcut, s)
        }
        return true
    }
}

