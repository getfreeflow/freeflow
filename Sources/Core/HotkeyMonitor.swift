import AppKit
import CoreGraphics

/// Watches for the configured trigger keys.
///
/// Four things make modifier-only hotkeys trickier than they look:
///
/// 1. Modifiers emit no key event at all, only a flag change, so we tap
///    `.flagsChanged` rather than `.keyDown`.
/// 2. Arrow keys, Home/End and Delete *also* set the fn mask on Mac keyboards, and
///    both ⌥ keys share one flag. So we match on the keycode of the physical key
///    that changed, and read that key's own flag bit to decide up vs down.
/// 3. The trigger keys are also real modifiers people use while typing. Recording on
///    every ⌘-down would fire on ⌘C. So a press only counts once it's been held
///    *alone* past `soloHoldDelay`. If another key joins in it's a chord and we
///    stay out of the way. A quick solo tap still counts: on release we report the
///    press and release back to back, which is what double-tap relies on.
/// 4. The tap runs on its own thread. macOS disables a tap whose thread stalls for
///    about a second, and the key-up in flight at that moment is gone for good. On
///    the main thread that happened whenever the UI or a Bluetooth mic was slow,
///    and the monitor was left thinking the key was still down, ignoring every
///    press after it.
///
/// The tap is `.listenOnly`: we observe and never consume, so every existing
/// shortcut keeps working exactly as before.
final class HotkeyMonitor {

    /// Delivered on the main queue.
    var onPress: ((TriggerRole) -> Void)?
    /// Delivered on the main queue, with how long the key was physically down.
    var onRelease: ((TriggerRole, TimeInterval) -> Void)?
    var onCancel: (() -> Void)?

    /// Rebound live from Settings, read from the event thread.
    var dictationKey: TriggerKey {
        get { keysLock.withLock { storedDictationKey } }
        set { keysLock.withLock { storedDictationKey = newValue } }
    }
    var commandKey: TriggerKey {
        get { keysLock.withLock { storedCommandKey } }
        set { keysLock.withLock { storedCommandKey = newValue } }
    }

    private(set) var isRunning = false

    private var storedDictationKey: TriggerKey = .fn
    private var storedCommandKey: TriggerKey = .off
    private let keysLock = NSLock()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?

    /// Key state below is only touched on this queue.
    private let queue = DispatchQueue(label: "FreeFlow.hotkey", qos: .userInteractive)

    /// A trigger is down but hasn't yet qualified as a solo hold.
    private var pending: (role: TriggerRole, keyCode: Int64, downAt: TimeInterval, work: DispatchWorkItem)?
    /// A trigger that has qualified and is currently driving a recording.
    private var active: (role: TriggerRole, keyCode: Int64, downAt: TimeInterval)?
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
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            isRunning = false
            return false
        }

        let handoff = RunLoopHandoff()
        let thread = Thread {
            let loop: CFRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            handoff.loop = loop
            handoff.ready.signal()
            CFRunLoopRun()
        }
        thread.name = "FreeFlow hotkey tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        handoff.ready.wait()

        tap = newTap
        runLoopSource = source
        tapRunLoop = handoff.loop
        CGEvent.tapEnable(tap: newTap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        queue.sync {
            pending?.work.cancel()
            pending = nil
            active = nil
            chordDetected = false
        }

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapRunLoop {
            if let runLoopSource {
                CFRunLoopRemoveSource(tapRunLoop, runLoopSource, .commonModes)
            }
            CFRunLoopStop(tapRunLoop)
        }
        tap = nil
        runLoopSource = nil
        tapRunLoop = nil
        isRunning = false
    }

    /// Runs on the tap thread. Does as little as possible and hands off, so the
    /// callback always returns immediately.
    fileprivate func receive(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Whatever happened while it was off is lost. Catch up from the
            // keyboard's actual state rather than trusting the last event seen.
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let now = ProcessInfo.processInfo.systemUptime
            queue.async { [weak self] in self?.resync(flags: flags, at: now) }

        case .flagsChanged, .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            // Stamped on arrival, not when handled, so hold durations are exact.
            let now = ProcessInfo.processInfo.systemUptime
            queue.async { [weak self] in
                self?.handle(type, keyCode: keyCode, flags: flags, at: now)
            }

        default:
            break
        }
    }

    // MARK: - Key state (on `queue`)

    private func handle(_ type: CGEventType, keyCode: Int64, flags: CGEventFlags, at time: TimeInterval) {
        if type == .keyDown {
            // Any real keypress while a trigger is held makes it a chord, not dictation.
            if pending != nil || active != nil {
                chordDetected = true
                pending?.work.cancel()
                pending = nil
            }
            if keyCode == Self.escapeKeyCode {
                DispatchQueue.main.async { [weak self] in self?.onCancel?() }
            }
            return
        }

        guard let (role, key) = role(forKeyCode: keyCode) else { return }

        if key.isDown(in: flags) {
            triggerDown(role: role, keyCode: keyCode, at: time)
        } else {
            triggerUp(keyCode: keyCode, at: time)
        }
    }

    private func triggerDown(role: TriggerRole, keyCode: Int64, at time: TimeInterval) {
        // Down again with no up in between means the up was lost. End the old press
        // instead of ignoring this one, which is how the key used to go dead.
        if let active, active.keyCode == keyCode {
            self.active = nil
            emitRelease(active.role, heldFor: time - active.downAt)
        }
        guard pending == nil, active == nil else { return }
        chordDetected = false

        let work = DispatchWorkItem { [weak self] in
            guard let self, let pending = self.pending, !self.chordDetected else { return }
            self.active = (pending.role, pending.keyCode, pending.downAt)
            self.pending = nil
            self.emitPress(pending.role)
        }
        pending = (role, keyCode, time, work)
        queue.asyncAfter(deadline: .now() + soloHoldDelay, execute: work)
    }

    private func triggerUp(keyCode: Int64, at time: TimeInterval) {
        // Released before it qualified as a hold.
        if let pending, pending.keyCode == keyCode {
            pending.work.cancel()
            self.pending = nil

            // A clean, fast solo tap still counts. Report both halves together so
            // the controller sees it as a tap.
            guard !chordDetected else { return }
            let role = pending.role
            let held = time - pending.downAt
            DispatchQueue.main.async { [weak self] in
                self?.onPress?(role)
                self?.onRelease?(role, held)
            }
            return
        }

        guard let active, active.keyCode == keyCode else { return }
        self.active = nil
        emitRelease(active.role, heldFor: time - active.downAt)
    }

    /// Releases anything we think is held but the keyboard says isn't. Uses the
    /// generic modifier flag, so it only ever acts when the key is certainly up.
    private func resync(flags: CGEventFlags, at time: TimeInterval) {
        if let pending, isCertainlyUp(pending.role, flags: flags) {
            triggerUp(keyCode: pending.keyCode, at: time)
        }
        if let active, isCertainlyUp(active.role, flags: flags) {
            triggerUp(keyCode: active.keyCode, at: time)
        }
    }

    private func isCertainlyUp(_ role: TriggerRole, flags: CGEventFlags) -> Bool {
        let key = role == .command ? commandKey : dictationKey
        guard let flag = key.flag else { return true }
        return !flags.contains(flag)
    }

    private func emitPress(_ role: TriggerRole) {
        DispatchQueue.main.async { [weak self] in self?.onPress?(role) }
    }

    private func emitRelease(_ role: TriggerRole, heldFor held: TimeInterval) {
        DispatchQueue.main.async { [weak self] in self?.onRelease?(role, held) }
    }

    private func role(forKeyCode keyCode: Int64) -> (TriggerRole, TriggerKey)? {
        let dictation = dictationKey
        let command = commandKey
        if dictation != .off, dictation.keyCode == keyCode {
            return (.dictation, dictation)
        }
        if command != .off, command.keyCode == keyCode {
            return (.command, command)
        }
        return nil
    }

    deinit { stop() }
}

/// Carries the tap thread's run loop back to `start()`.
private final class RunLoopHandoff: @unchecked Sendable {
    var loop: CFRunLoop?
    let ready = DispatchSemaphore(value: 0)
}

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue().receive(type: type, event: event)
    }
    // Always pass the event through untouched.
    return Unmanaged.passUnretained(event)
}
