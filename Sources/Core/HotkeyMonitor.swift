import AppKit
import CoreGraphics

/// Watches for the configured trigger keys.
///
/// Three problems make modifier-only hotkeys trickier than they look:
///
/// 1. Modifiers emit no key event at all, only a flag change, so we tap
///    `.flagsChanged` rather than `.keyDown`.
/// 2. Arrow keys, Home/End and Delete *also* set the fn mask on Mac keyboards, and
///    both ⌥ keys share one flag. Watching flags alone would fire on every arrow
///    press and couldn't tell left-⌥ from right-⌥, so we match on the keycode of the
///    physical key that changed and use the flag only to decide up vs down.
/// 3. The trigger keys are also real modifiers people use while typing. Recording on
///    every ⌘-down would fire on ⌘C. So a press only counts once it's been held
///    *alone* past `soloHoldDelay`. If another key joins in it's a chord and we
///    stay out of the way. A quick solo tap still works: on release we fire the
///    press and release back to back so tap-to-latch behaves as expected.
///
/// The tap is `.listenOnly`: we observe and never consume, so every existing
/// shortcut keeps working exactly as before.
final class HotkeyMonitor {

    var onPress: ((TriggerRole) -> Void)?
    var onRelease: ((TriggerRole) -> Void)?
    var onCancel: (() -> Void)?

    /// Rebound live from Settings.
    var dictationKey: TriggerKey = .fn
    var commandKey: TriggerKey = .off

    private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// A trigger is down but hasn't yet qualified as a solo hold.
    private var pending: (role: TriggerRole, keyCode: Int64, work: DispatchWorkItem)?
    /// A trigger that has qualified and is currently driving a recording.
    private var active: (role: TriggerRole, keyCode: Int64)?
    /// Set when another key is pressed while a trigger is held. Marks it a chord.
    private var chordDetected = false

    private let soloHoldDelay: TimeInterval = 0.12
    private static let escapeKeyCode: Int64 = 53

    /// Returns false when macOS refuses the tap, which in practice always means
    /// Accessibility / Input Monitoring hasn't been granted yet.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isRunning = false
            return false
        }

        tap = newTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        pending?.work.cancel()
        pending = nil
        active = nil
        chordDetected = false

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that block for too long; switch it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .flagsChanged:
            handleFlagsChanged(event)

        case .keyDown:
            // Any real keypress while a trigger is held makes it a chord, not dictation.
            if pending != nil || active != nil {
                chordDetected = true
                pending?.work.cancel()
                pending = nil
            }
            if event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode {
                DispatchQueue.main.async { [weak self] in self?.onCancel?() }
            }

        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let (role, key) = role(forKeyCode: keyCode), let flag = key.flag else { return }

        if event.flags.contains(flag) {
            triggerDown(role: role, keyCode: keyCode)
        } else {
            triggerUp(keyCode: keyCode)
        }
    }

    private func triggerDown(role: TriggerRole, keyCode: Int64) {
        guard pending == nil, active == nil else { return }
        chordDetected = false

        let work = DispatchWorkItem { [weak self] in
            guard let self, let pending = self.pending, !self.chordDetected else { return }
            self.active = (pending.role, pending.keyCode)
            self.pending = nil
            self.onPress?(pending.role)
        }
        pending = (role, keyCode, work)
        DispatchQueue.main.asyncAfter(deadline: .now() + soloHoldDelay, execute: work)
    }

    private func triggerUp(keyCode: Int64) {
        // Released before it qualified as a hold.
        if let pending, pending.keyCode == keyCode {
            pending.work.cancel()
            self.pending = nil

            // A clean, fast solo tap still counts, so fire press and release together and
            // the controller's tap-to-latch logic sees it.
            guard !chordDetected else { return }
            let role = pending.role
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onPress?(role)
                self.onRelease?(role)
            }
            return
        }

        guard let active, active.keyCode == keyCode else { return }
        self.active = nil
        let role = active.role
        DispatchQueue.main.async { [weak self] in self?.onRelease?(role) }
    }

    private func role(forKeyCode keyCode: Int64) -> (TriggerRole, TriggerKey)? {
        if dictationKey != .off, dictationKey.keyCode == keyCode {
            return (.dictation, dictationKey)
        }
        if commandKey != .off, commandKey.keyCode == keyCode {
            return (.command, commandKey)
        }
        return nil
    }

    deinit { stop() }
}

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    }
    // Always pass the event through untouched.
    return Unmanaged.passUnretained(event)
}
