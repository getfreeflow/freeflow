import AppKit
import CoreGraphics

/// Puts text into whatever app is frontmost.
///
/// Two routes, best-first:
///
/// 1. **Accessibility write.** Asks the focused field to replace its selection
///    directly. Leaves the clipboard completely untouched and preserves the app's
///    own undo stack. Only used when the field reports the attribute as settable,
///    so we never silently drop text into something that ignores it.
/// 2. **Pasteboard + synthetic ⌘V.** The universal fallback. Works in essentially
///    every app including Electron ones. The previous clipboard contents are
///    restored afterwards so dictating doesn't clobber what you had copied.
/// 3. **Clipboard only.** When nothing focused can take text. Firing ⌘V at nothing
///    would look identical to losing the dictation, so instead the text is left on
///    the clipboard (and *not* restored afterwards) for the user to paste themselves.
enum TextInjector {

    enum Result: Equatable {
        /// Landed in the focused field.
        case inserted
        /// Nowhere to put it; left on the clipboard for the user.
        case copiedToClipboard
    }

    private static let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V

    @discardableResult
    static func inject(_ text: String, preferDirectWrite: Bool) -> Result {
        guard !text.isEmpty else { return .inserted }

        guard SelectionReader.focusedFieldLooksEditable() else {
            copy(text)
            return .copiedToClipboard
        }

        if preferDirectWrite,
           SelectionReader.focusedFieldAcceptsDirectWrite(),
           SelectionReader.writeToFocusedField(text) {
            return .inserted
        }

        paste(text)
        return .inserted
    }

    /// Leaves the text on the clipboard permanently. The previous contents are not
    /// restored, because here the clipboard *is* the delivery mechanism.
    private static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCommandV()

        // Restore once the paste has had time to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard let previousContents else { return }
            pasteboard.clearContents()
            pasteboard.setString(previousContents, forType: .string)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
