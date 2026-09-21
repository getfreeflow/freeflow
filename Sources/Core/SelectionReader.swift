import ApplicationServices
import Foundation

/// Reads the text currently selected in whatever app is frontmost.
///
/// This is what makes Command Mode work on existing text. Select a paragraph, hold
/// the command key, say "make this shorter", and the rewrite replaces the selection.
enum SelectionReader {

    static func selectedText() -> String? {
        guard let element = focusedElement(),
              let selected = copyAttribute(element, kAXSelectedTextAttribute) as? String,
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return selected
    }

    /// True when the focused field will accept a direct Accessibility write, which
    /// inserts text without touching the clipboard at all.
    static func focusedFieldAcceptsDirectWrite() -> Bool {
        guard let element = focusedElement() else { return false }
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        return status == .success && settable.boolValue
    }

    /// Roles that definitively can't take text. Deliberately a deny-list rather than
    /// an allow-list: an unrecognised role is far more likely to be some app's custom
    /// editor than a button, and pasting into the wrong place is recoverable while
    /// silently withholding text is not.
    private static let nonEditableRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXMenuBarItem",
        "AXImage", "AXStaticText", "AXSlider", "AXScrollBar", "AXLink",
        "AXDisclosureTriangle", "AXPopUpButton", "AXToolbar", "AXTabGroup"
    ]

    /// Whether there's somewhere for text to actually go.
    ///
    /// When this is false the caller should leave the text on the clipboard instead
    /// of firing ⌘V into nothing. A paste with no destination looks to the user
    /// exactly like the dictation was lost.
    ///
    /// Only answers no when it knows. Chromium and Electron apps (Chrome, Slack,
    /// Claude, VS Code) report no focused element at all unless a screen reader is
    /// running, and treating that silence as "nowhere to type" sent every dictation
    /// in them to the clipboard.
    static func focusedFieldLooksEditable() -> Bool {
        guard let element = focusedElement() else { return true }

        if let role = copyAttribute(element, kAXRoleAttribute) as? String,
           nonEditableRoles.contains(role) {
            return false
        }
        return true
    }

    /// Writes directly into the focused field, replacing any selection.
    @discardableResult
    static func writeToFocusedField(_ text: String) -> Bool {
        guard let element = focusedElement() else { return false }
        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return status == .success
    }

    // MARK: - Private

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        guard let focused = copyAttribute(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
