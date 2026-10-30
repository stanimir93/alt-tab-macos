import Cocoa
import Darwin
import Carbon.HIToolbox.Events

class NoAnimationDelegate: NSObject, CALayerDelegate {
    static let shared = NoAnimationDelegate()
    func action(for layer: CALayer, forKey event: String) -> (any CAAction)? { NSNull() }
}

func noAnimation<T: CALayer>(_ make: () -> T) -> T {
    let layer = make()
    layer.delegate = NoAnimationDelegate.shared
    return layer
}

func caTransaction(_ body: () -> Void) {
    CATransaction.begin()
    defer { CATransaction.commit() }
    CATransaction.setDisableActions(true)
    body()
}

extension NSAppearance {
    func getThemeName() -> AppearanceThemePreference {
        let appearance = NSApp.effectiveAppearance.name
        return appearance == .darkAqua || appearance == .vibrantDark ? .dark : .light
    }
}

extension NSColor {
    /// Dynamically adapts to changes in System Settings; no need to listen to notifications.
    class var systemAccentColor: NSColor {
        NSColor.controlAccentColor
    }
}

extension CALayer {
    func centerInSuperlayer(x: Bool = false, y: Bool = false) {
        guard let superlayer else { return }
        if x { frame.origin.x = ((superlayer.bounds.width - frame.width) / 2).rounded() }
        if y { frame.origin.y = ((superlayer.bounds.height - frame.height) / 2).rounded() }
    }

    func applyShadow(_ shadow: NSShadow?) {
        guard let shadow else { shadowOpacity = 0; return }
        shadowColor = shadow.shadowColor?.cgColor
        shadowOffset = shadow.shadowOffset
        shadowRadius = shadow.shadowBlurRadius
        shadowOpacity = 1.0
    }
}

extension NSView {
    // constrain size to fittingSize
    func fit() {
        addOrUpdateConstraint(widthAnchor, fittingSize.width)
        addOrUpdateConstraint(heightAnchor, fittingSize.height)
    }

    // constrain size to provided width and height
    func fit(_ width: CGFloat, _ height: CGFloat) {
        addOrUpdateConstraint(widthAnchor, width)
        addOrUpdateConstraint(heightAnchor, height)
    }

    func addOrUpdateConstraint(_ anchor: NSLayoutDimension, _ constant: CGFloat) {
        if let constraint = (constraints.first { $0.firstAnchor == anchor && $0.secondAnchor == nil }) {
            constraint.constant = constant
        } else {
            anchor.constraint(equalToConstant: constant).isActive = true
        }
    }

    func addSubviews(_ views: [NSView]) {
        subviews = subviews + views
    }

    func setSubviewAbove(_ view: NSView) {
        addSubview(view, positioned: .above, relativeTo: nil)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// only assign if different; useful for performance
func assignIfDifferent<T: Equatable>(_ a: UnsafeMutablePointer<T>, _ b: T) {
    if a.pointee != b {
        a.pointee = b
    }
}

extension DispatchQoS {
    func toQualityOfService() -> QualityOfService {
        switch self {
            case .userInteractive: return .userInteractive
            case .userInitiated: return .userInitiated
            case .utility: return .utility
            case .background: return .background
            default: return .default
        }
    }
}

extension CGImage {
    func size() -> NSSize {
        return NSSize(width: width, height: height)
    }
}

extension CVPixelBuffer {
    func size() -> NSSize {
        NSSize(
            width: CVPixelBufferGetWidth(self),
            height: CVPixelBufferGetHeight(self)
        )
    }
}

extension String {
    // convert a FourCharCode into a String
    init(_ fourCharCode: FourCharCode) { // or `OSType`, or `UInt32`
        self = NSFileTypeForHFSTypeCode(fourCharCode).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }
}

/// Whether AltTab's non-switcher windows may take key focus. They are only ever flipped together,
/// while the switcher's panel is ordered out: a window taking key focus there would steal it from the
/// app the user is switching to (`App.hideTilesPanelWithoutChangingKeyWindow`).
enum SecondaryWindows {
    static var canBecomeKey = true
}

extension NSPanel {
    /// The chrome AltTab's two floating panels (the switcher and the window preview) share.
    /// `.canJoinAllSpaces` matters because triggering AltTab before or during a Space transition
    /// otherwise only brings the panel over once the transition ends. The `.unknown` accessibility
    /// subrole is what keeps these panels out of AltTab's own thumbnails.
    func applyFloatingPanelChrome() {
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        backgroundColor = .clear
        collectionBehavior = .canJoinAllSpaces
        setAccessibilitySubrole(.unknown)
    }
}

extension NSSearchField {
    /// The switcher's search field and the settings sidebar's look the same and both want every
    /// keystroke rather than a debounced one. `controlSize` tracks the OS: macOS 26 draws search
    /// fields as a taller pill, and 13 through 15 as the `.large` bezel.
    func applySearchStyle() {
        placeholderString = NSLocalizedString("Search", comment: "")
        sendsSearchStringImmediately = true
        sendsWholeSearchString = true
        bezelStyle = .roundedBezel
        if #available(macOS 26.0, *) {
            controlSize = .extraLarge
        } else if #available(macOS 13.0, *) {
            controlSize = .large
        }
    }
}

extension NotificationCenter {
    /// Drop a stored observer token. Nilling the token matters as much as the removal: the
    /// re-subscribe guards elsewhere read `observer == nil` to decide whether to observe again.
    func removeObserver(_ observer: inout NSObjectProtocol?) {
        guard let token = observer else { return }
        removeObserver(token)
        observer = nil
    }
}

extension NSWindow {
    /// The chrome every secondary window shares: a title that only shows in the Window menu and in
    /// Mission Control, and a window that survives both being closed and the app deactivating.
    /// `hiddenTitlebar` is what makes the content extend under the traffic lights; the Debug window
    /// keeps a real titlebar because it is resizable.
    func applySecondaryWindowChrome(_ title: String, hiddenTitlebar: Bool = true) {
        self.title = title
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        if hiddenTitlebar {
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
        }
    }

    func hideAppIfLastWindowIsClosed() {
        if (!NSApp.windows.contains { $0.isVisible && $0.className != "NSStatusBarWindow" && $0.windowNumber != windowNumber }) {
            App.shared.hide(nil)
        }
    }

    /// Safe replacement for `setFrameAutosaveName`: that call doesn't just register a name, it
    /// immediately applies the frame persisted under "NSWindow Frame <name>". A corrupt persisted
    /// frame makes that apply throw and aborts the app (crash f481d5b0). Drop the bad
    /// value first so AppKit never sees it. Returns whether a valid saved frame is present.
    @discardableResult
    func setFrameAutosaveNameSafely(_ name: NSWindow.FrameAutosaveName) -> Bool {
        let key = "NSWindow Frame \(name)"
        let saved = UserDefaults.standard.string(forKey: key)
        let valid = saved.map { Self.isValidPersistedFrame($0) } ?? false
        if saved != nil && !valid {
            Logger.debug { "Dropping corrupt persisted frame for \(key): \(saved)" }
            UserDefaults.standard.removeObject(forKey: key)
        }
        setFrameAutosaveName(name)
        return valid
    }
}

extension CaseIterable where Self: Equatable {
    var index: Int {
        return Self.allCases.distance(from: Self.allCases.startIndex, to: Self.allCases.firstIndex(of: self)!)
    }
    var indexAsString: String {
        return String(describing: self.index)
    }
}

class ModifierFlags {
    static var current: NSEvent.ModifierFlags {
        return NSEvent.modifierFlags
    }
}

extension Optional {
    enum Error: Swift.Error {
        case unexpectedNil
    }

    // useful call multiple statements that could fail, and have a unique do-catch block to handle failures
    func unwrapOrThrow() throws -> Wrapped {
        if let self { return self } else { throw Error.unexpectedNil }
    }
}

extension NSRunningApplication {
    func debugId() -> String { "(pid:\(processIdentifier) \(bundleIdentifier ?? bundleURL?.absoluteString ?? executableURL?.absoluteString ?? localizedName))" }
}

/// this changes the behavior of interpolating optional values (e.g. "\(optionalValue)")
/// default is to return a compiler warning "string interpolation produces a debug description for an optional value; did you mean to make this explicit?"
/// instead, we either print the value, or print "nil"
extension String.StringInterpolation {
    mutating func appendInterpolation<T>(_ value: T?) {
        if let value {
            appendInterpolation(value)
        } else {
            appendLiteral("nil")
        }
    }
}

extension CGEvent {
    func toNSEvent() -> NSEvent? {
        if Thread.isMainThread {
            return NSEvent(cgEvent: self)
        }
        // conversion has to happen on the main-thread, or appkit will crash
        var nsEvent: NSEvent?
        DispatchQueue.main.sync {
            nsEvent = NSEvent(cgEvent: self)
        }
        return nsEvent
    }

    /// Create an event tap and put it on `runLoop`. `tapCreate` returns nil when the Accessibility
    /// permission isn't granted, and every input tap we install is load-bearing, so that case restarts
    /// the app rather than running on with a dead tap.
    static func createTapOrRestart(tap: CGEventTapLocation, options: CGEventTapOptions, eventsOfInterest: CGEventMask,
                                   callback: @escaping CGEventTapCallBack, runLoop: CFRunLoop?) -> CFMachPort? {
        guard let port = CGEvent.tapCreate(tap: tap, place: .headInsertEventTap, options: options,
            eventsOfInterest: eventsOfInterest, callback: callback, userInfo: nil) else {
            App.restart()
            return nil
        }
        CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        return port
    }

    /// macOS disables taps on sleep and on a callback timeout (#5723). Put one back in the stream if we
    /// still want it on. Returns whether it re-enabled, so each caller logs its own wording.
    static func reEnableTapIfNeeded(_ port: CFMachPort?, wanted: Bool) -> Bool {
        guard let port, wanted, !CGEvent.tapIsEnabled(tap: port) else { return false }
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
}
