import Cocoa

extension NSAlert {
    /// Attaches the alert to `window`, or to the sheet already on it, when it is on screen; otherwise
    /// the alert is app-modal.
    func present(attachedTo window: NSWindow?, _ completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let parent = Self.sheetParent(window) else { return completion(runModal()) }
        beginSheetModal(for: parent, completionHandler: completion)
    }

    /// The same, for callers that need the answer before returning: the sheet runs its own modal loop.
    /// An aborted loop (`NSApp.abortModal`) answers `.abort`, which no caller treats as a button.
    func runAttached(to window: NSWindow?) -> NSApplication.ModalResponse {
        guard let parent = Self.sheetParent(window) else { return runModal() }
        beginSheetModal(for: parent) { [weak self] response in
            guard NSApp.modalWindow === self?.window else { return }
            NSApp.stopModal(withCode: response)
        }
        return NSApp.runModal(for: self.window)
    }

    private static func sheetParent(_ window: NSWindow?) -> NSWindow? {
        guard var parent = window, parent.isVisible else { return nil }
        while let sheet = parent.attachedSheet { parent = sheet }
        return parent
    }
}
