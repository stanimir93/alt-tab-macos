import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class KeyboardEvents {
    private static let signature = "altt".utf16.reduce(0) { ($0 << 8) + OSType($1) }
    // GetEventMonitorTarget/GetApplicationEventTarget also work, but require Accessibility Permission
    private static let shortcutEventTarget = GetEventDispatcherTarget()
    private static var eventHotKeyRefs = [String: EventHotKeyRef?]()
    private static var hotKeyPressedEventHandler: EventHandlerRef?
    private static var hotKeyReleasedEventHandler: EventHandlerRef?
    private static var globalShortcutsAreDisabled = false
    /// Permanent passive tap on `cgSessionEventTap` + `.listenOnly`. Flags drive hold-shortcut triggering;
    /// key-downs only preserve source order for Carbon hotkeys delayed behind a main-thread stall.
    private static var eventTap: CFMachPort?
    /// `.keyDown` tap on `cghidEventTap` + `.defaultTap`, used only to absorb Esc ahead of macOS 26
    /// Game Overlay (#5585). Created DISABLED; enabled only while a switcher session is open and a
    /// shortcut binds Esc (`updateEscapeAbsorptionTap`). Keeping this active HID keyDown tap out of
    /// normal typing is the #5766 fix (it was breaking third-party IMEs like Vietnamese EVKey).
    private static var escapeEventTap: CFMachPort?
    // periphery:ignore - holds the monitor token so the handler stays installed
    private static var localEventMonitor: Any?

    /// Set by `ControlsTab` when the configured shortcuts change. When true and `SwitcherSession.isActive`,
    /// our `escapeEventTap` absorbs Esc keyDowns and routes them through the matcher. Issue #5585:
    /// this is the only path that beats macOS 26 Game Overlay's hook on `⌘⎋`. Also gates whether
    /// `escapeEventTap` is enabled at all (see `updateEscapeAbsorptionTap`).
    static var anyShortcutUsesEscape = false

    /// Each nextWindowShortcut with ⇧ added (⌘⇧⇥ for ⌘⇥) summons the switcher on its last window, then
    /// cycles backwards, like the native reverse switcher. `NativeHotkeyResolver` disables native ⌘⇧⇥
    /// whenever ⌘⇥ is bound, and previousWindowShortcut is local, so without these the chord does nothing
    /// while the switcher is closed. They derive from nextWindowShortcut and have no setting of their own,
    /// so they stay out of `ControlsTab.shortcuts` and its conflict checks.
    private(set) static var reverseShortcuts = [String: ATShortcut]()

    private static let inputEventHandler: CGEventTapCallBack = { _, type, cgEvent, _ in
        switch type {
        case .flagsChanged:
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
            ModifierReleaseLog.record(modifiers)
            DispatchQueue.main.async {
                handleKeyboardEvent(nil, nil, nil, modifiers, false)
            }
            return Unmanaged.passUnretained(cgEvent)
        case .keyDown:
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
            let keyCode = UInt32(cgEvent.getIntegerValueField(.keyboardEventKeycode))
            let isARepeat = cgEvent.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if let keySequence = ModifierReleaseLog.recordKeyDown(keyCode, modifiers, isARepeat: isARepeat) {
                forgetIfNeverReported(keySequence)
            }
            return Unmanaged.passUnretained(cgEvent)
        case .tapDisabledByUserInput, .tapDisabledByTimeout:
            Logger.info { "input tap \(type == .tapDisabledByTimeout ? "timed out" : "was disabled by user input")" }
            reEnableTapIfNeeded()
            return Unmanaged.passUnretained(cgEvent)
        default:
            return Unmanaged.passUnretained(cgEvent)
        }
    }

    private static let escapeEventHandler: CGEventTapCallBack = { _, type, cgEvent, _ in
        switch type {
        case .keyDown:
            // Issue #5585. Esc only — absorb when AltTab is using it and a shortcut binds it. cghid is
            // the earliest tap point; absorbing here preempts macOS 26 Game Overlay's hook on `⌘⎋`.
            if cgEvent.getIntegerValueField(.keyboardEventKeycode) != Int64(kVK_Escape) ||
                !anyShortcutUsesEscape || !SwitcherSession.isActive {
                return Unmanaged.passUnretained(cgEvent)
            }
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
            let isARepeat = cgEvent.getIntegerValueField(.keyboardEventAutorepeat) != 0
            DispatchQueue.main.async {
                handleKeyboardEvent(nil, nil, UInt32(kVK_Escape), modifiers, isARepeat, nil)
            }
            return nil
        case .tapDisabledByUserInput, .tapDisabledByTimeout:
            // Logged at INFO, and naming WHICH cause, because a dead keyboard tap is invisible from the
            // outside: the symptom is "Esc does nothing and the switcher is stuck", and nothing in the
            // log said a tap had died. `byTimeout` means our own callback was too slow — the main thread
            // was busy — and it is the one worth chasing; `byUserInput` is macOS being defensive.
            //
            Logger.info { "\(type == .tapDisabledByTimeout ? "byTimeout" : "byUserInput") wantEscapeTap:\(anyShortcutUsesEscape && SwitcherSession.isActive)" }
            reEnableTapIfNeeded()
            return Unmanaged.passUnretained(cgEvent)
        default:
            return Unmanaged.passUnretained(cgEvent)
        }
    }

    /// Carbon delivers the hotkey on main, so the 1s only starts once main is free: a hotkey delayed behind a
    /// stall (F-08) is claimed before its key-down is forgotten.
    private static func forgetIfNeverReported(_ keySequence: UInt64) {
        DispatchQueue.main.async {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ModifierReleaseLog.forgetUnreported(keySequence) }
        }
    }

    /// The reverse hotkeys are dropped before registering `controlId`: Carbon refuses a chord that is
    /// already registered, and the reverse of one shortcut can be exactly the chord another is set to.
    static func addGlobalShortcut(_ controlId: String, _ shortcut: Shortcut) {
        addGlobalHandlerIfNeeded(shortcut)
        unregisterReverseShortcuts()
        registerHotKeyIfNeeded(controlId, shortcut)
        registerReverseShortcuts()
        ModifierReleaseLog.setSwitchingChords(switchingChords())
    }

    private static func unregisterReverseShortcuts() {
        reverseShortcuts.values.forEach { unregisterHotKeyIfNeeded($0.id, $0.shortcut) }
        reverseShortcuts = [:]
    }

    private static func registerReverseShortcuts(excluding removedControlId: String? = nil) {
        let globals = ControlsTab.shortcuts.values.filter { $0.scope == .global && $0.id != removedControlId }
        for next in globals where next.id.hasPrefix("nextWindowShortcut") {
            guard let reverse = reverseShortcut(next), !globals.contains(where: { chord($0) == chord(reverse) }) else { continue }
            reverseShortcuts[reverse.id] = reverse
            if !globalShortcutsAreDisabled { registerHotKeyIfNeeded(reverse.id, reverse.shortcut) }
        }
    }

    private static func reverseShortcut(_ next: ATShortcut) -> ATShortcut? {
        guard next.shortcut.keyCode != .none, !next.shortcut.modifierFlags.contains(.shift) else { return nil }
        let shortcut = Shortcut(code: next.shortcut.keyCode, modifierFlags: next.shortcut.modifierFlags.union(.shift),
                                characters: nil, charactersIgnoringModifiers: nil)
        let index = Preferences.nameToIndex(next.id)
        return ATShortcut(shortcut, Preferences.indexToName("reverseNextWindowShortcut", index), .global, .down, index)
    }

    private static func reverseShortcut(_ globalId: Int) -> ATShortcut? {
        reverseShortcuts.values.first { KeyboardEventsTestable.globalShortcutsIds[$0.id] == globalId }
    }

    private static func handleReverseShortcut(_ reverse: ATShortcut, _ state: ShortcutState) {
        reverse.state = state
        guard state == .down else {
            KeyRepeatTimer.stopTimerForRepeatingKey(reverse.id)
            return
        }
        settleLostHoldRelease()
        guard reverse.shouldTrigger() else { return }
        reverse.executeAction(false)
    }

    private static func claimRecordedRelease(_ globalId: Int) -> Bool {
        guard let controlId = KeyboardEventsTestable.globalShortcutsIds.first(where: { $0.value == globalId })?.key,
              controlId.hasPrefix("nextWindowShortcut"), let control = ControlsTab.shortcuts[controlId],
              let hold = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", Preferences.nameToIndex(controlId))]
        else { return false }
        return ModifierReleaseLog.claimRelease(after: chord(control),
                                               holdModifiers: hold.shortcut.carbonModifierFlags)
    }

    /// `ControlsTab.shortcuts` still lists a shortcut being removed when its unregistration runs, hence
    /// `excluding`.
    private static func switchingChords(excluding removedControlId: String? = nil) -> Set<ModifierReleaseLog.Chord> {
        Set(ControlsTab.shortcuts.values
            .filter { $0.id.hasPrefix("nextWindowShortcut") && $0.id != removedControlId }
            .map { chord($0) })
    }

    private static func chord(_ shortcut: ATShortcut) -> ModifierReleaseLog.Chord {
        ModifierReleaseLog.Chord(keyCode: shortcut.shortcut.carbonKeyCode,
                                 modifiers: shortcut.shortcut.carbonModifierFlags)
    }

    static func removeGlobalShortcut(_ controlId: String, _ shortcut: Shortcut) {
        unregisterHotKeyIfNeeded(controlId, shortcut)
        unregisterReverseShortcuts()
        registerReverseShortcuts(excluding: controlId)
        removeHandlerIfNeeded()
        ModifierReleaseLog.setSwitchingChords(switchingChords(excluding: controlId))
    }

    static func toggleGlobalShortcuts(_ shouldDisable: Bool) {
        if shouldDisable != globalShortcutsAreDisabled {
            let fn = shouldDisable ? unregisterHotKeyIfNeeded : registerHotKeyIfNeeded
            for shortcutId in KeyboardEventsTestable.globalShortcutsIds.keys {
                if let shortcut = (ControlsTab.shortcuts[shortcutId] ?? reverseShortcuts[shortcutId])?.shortcut {
                    fn(shortcutId, shortcut)
                }
            }
            Logger.info { "disabled:\(shouldDisable)" }
            globalShortcutsAreDisabled = shouldDisable
            ModifierReleaseLog.reset()
        }
    }

    static func reEnableTapIfNeeded() {
        if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            ModifierReleaseLog.reset()
            Logger.warning { "input tap was disabled; re-enabled" }
        }
        // `updateEscapeAbsorptionTap` covers the Esc tap: it compares `tapIsEnabled` against what it
        // wants, so a tap macOS disabled while the switcher is open is re-enabled by that comparison.
        updateEscapeAbsorptionTap()
    }

    /// Enables `escapeEventTap` only while it can do something useful: a switcher session is open AND
    /// a shortcut binds Esc. Outside that window it stays disabled, so the active HID `.keyDown` tap is
    /// never in the path during normal typing (#5766). Idempotent; safe from any thread; a no-op before
    /// the tap exists (e.g. unit tests that set `SwitcherSession.current` directly).
    static func updateEscapeAbsorptionTap() {
        guard let escapeEventTap else { return }
        let shouldEnable = anyShortcutUsesEscape && SwitcherSession.isActive
        if CGEvent.tapIsEnabled(tap: escapeEventTap) != shouldEnable {
            CGEvent.tapEnable(tap: escapeEventTap, enable: shouldEnable)
            // Whether Esc can be heard while the switcher is up is the difference between "press Esc" and
            // "no way out", and it was not visible anywhere. Cheap: this fires twice per summon.
            Logger.debug { "escape tap enabled:\(shouldEnable) usesEscape:\(anyShortcutUsesEscape) sessionActive:\(SwitcherSession.isActive)" }
        }
    }

    static func addEventHandlers() {
        addLocalMonitorForKeyDownAndKeyUp()
        addCgEventTap()
    }

    private static func unregisterHotKeyIfNeeded(_ controlId: String, _ shortcut: Shortcut) {
        if shortcut.keyCode != .none {
            let key = shortcut.carbonKeyCode
            let mods = shortcut.carbonModifierFlags
            if let ref = eventHotKeyRefs[controlId] {
                let status = UnregisterEventHotKey(ref)
                if status == noErr {
                    Logger.debug { "unregistered \(controlId) keyCode:\(key) modifiers:\(mods)" }
                } else {
                    Logger.error { "UnregisterEventHotKey failed for \(controlId) keyCode:\(key) modifiers:\(mods) status:\(status)" }
                }
                eventHotKeyRefs[controlId] = nil
            }
        }
    }

    private static func registerHotKeyIfNeeded(_ controlId: String, _ shortcut: Shortcut) {
        if shortcut.keyCode != .none {
            guard let id = KeyboardEventsTestable.globalShortcutsIds[controlId] else { return }
            let hotkeyId = EventHotKeyID(signature: signature, id: UInt32(id))
            let key = shortcut.carbonKeyCode
            let mods = shortcut.carbonModifierFlags
            let options = UInt32(kEventHotKeyNoOptions)
            var shortcutsReference: EventHotKeyRef?
            let status = RegisterEventHotKey(key, mods, hotkeyId, shortcutEventTarget, options, &shortcutsReference)
            if status == noErr {
                Logger.debug { "registered \(controlId) keyCode:\(key) modifiers:\(mods)" }
            } else {
                Logger.error { "RegisterEventHotKey failed for \(controlId) keyCode:\(key) modifiers:\(mods) status:\(status)" }
            }
            eventHotKeyRefs[controlId] = shortcutsReference
        }
    }

    // TODO: handle this on a background thread?
    private static func addLocalMonitorForKeyDownAndKeyUp() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { (event: NSEvent) in
            if DismissalInput.discard(event) { return nil }
            let keyCode = event.type == .keyDown ? UInt32(event.keyCode) : nil
            let isARepeat = event.type == .keyDown ? event.isARepeat : false
            let shouldAbsorbEvent = handleKeyboardEvent(nil, nil, keyCode, event.modifierFlags, isARepeat, event)
            // A key can settle a delayed hold release and close the switcher before this monitor returns it.
            if DismissalInput.discard(event) { return nil }
            return shouldAbsorbEvent ? nil : event
        }
    }

    private static func addCgEventTap() {
        // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass.
        // SecureInput does not block `.flagsChanged` on either cgSession or cghid taps; `.keyDown` is
        // filtered out at the system level for both.
        //
        // Two taps. The session tap is passive: flags drive hold-shortcut triggering, while key-downs are
        // only recorded to preserve their order relative to those flags when Carbon drains late. It never
        // handles or suppresses typing. The Esc tap is cghid + defaultTap (the only way to swallow Esc ahead
        // of macOS 26 Game Overlay, #5585); it is disabled outside a switcher session, keeping the active HID
        // path out of normal typing for #5766.
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: [CGEventType.flagsChanged, .keyDown]
                .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) },
            callback: inputEventHandler,
            userInfo: nil)
        guard let eventTap else { App.restart(); return }
        addToKeyboardRunLoop(eventTap)
        escapeEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: escapeEventHandler,
            userInfo: nil)
        guard let escapeEventTap else { App.restart(); return }
        CGEvent.tapEnable(tap: escapeEventTap, enable: false)
        addToKeyboardRunLoop(escapeEventTap)
        updateEscapeAbsorptionTap()
    }

    private static func addToKeyboardRunLoop(_ tap: CFMachPort) {
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(BackgroundWork.keyboardAndMouseAndTrackpadEventsThread.runLoop, runLoopSource, .commonModes)
    }

    private static func addGlobalHandlerIfNeeded(_ shortcut: Shortcut) {
        if shortcut.keyCode != .none && hotKeyPressedEventHandler == nil {
            var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))]
            InstallEventHandler(shortcutEventTarget, { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                let globalId = Int(id.id)
                if let reverse = KeyboardEvents.reverseShortcut(globalId) {
                    KeyboardEvents.handleReverseShortcut(reverse, .down)
                    return noErr
                }
                handleKeyboardEvent(globalId, .down, nil, nil, false, nil,
                                    KeyboardEvents.claimRecordedRelease(globalId))
                return noErr
            }, eventTypes.count, &eventTypes, nil, &hotKeyPressedEventHandler)
        }
        if shortcut.keyCode != .none && hotKeyReleasedEventHandler == nil {
            var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased))]
            InstallEventHandler(shortcutEventTarget, { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                if let reverse = KeyboardEvents.reverseShortcut(Int(id.id)) {
                    KeyboardEvents.handleReverseShortcut(reverse, .up)
                    return noErr
                }
                handleKeyboardEvent(Int(id.id), .up, nil, nil, false)
                return noErr
            }, eventTypes.count, &eventTypes, nil, &hotKeyReleasedEventHandler)
        }
    }

    private static func removeHandlerIfNeeded() {
        let globalShortcuts = ControlsTab.shortcuts.values.filter { $0.scope == .global }
        if let hotKeyPressedEventHandler_ = hotKeyPressedEventHandler, let hotKeyReleasedEventHandler_ = hotKeyReleasedEventHandler,
           (globalShortcuts.allSatisfy { $0.shortcut.keyCode == .none }) {
            RemoveEventHandler(hotKeyPressedEventHandler_)
            hotKeyPressedEventHandler = nil
            RemoveEventHandler(hotKeyReleasedEventHandler_)
            hotKeyReleasedEventHandler = nil
        }
    }
}
