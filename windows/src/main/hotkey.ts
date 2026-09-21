import { uIOhook } from 'uiohook-napi';

/// Watches for the trigger key.
///
/// Same rules as the Mac version, which were arrived at the hard way:
///
/// 1. The trigger is a key people also type with. Right Alt is AltGr on many
///    European layouts, so firing the moment it goes down would start a recording
///    every time someone typed an accented character. A press only counts once it
///    has been held *alone* past `SOLO_HOLD_MS`; if another key joins in it's a
///    chord and we stay out of the way.
/// 2. A quick solo tap still counts. On release we report the press and the release
///    back to back, which is what double-tap-to-lock relies on.
/// 3. Windows repeats key-down events while a key is held. Only the first counts.
///
/// The hook observes without consuming, so every existing shortcut keeps working.

const SOLO_HOLD_MS = 120;
const ESCAPE_KEYCODE = 1;

export interface HotkeyHandlers {
  onPress: () => void;
  /** With how long the key was physically held, so the caller can tell a tap from a hold. */
  onRelease: (heldMs: number) => void;
  onEscape: () => void;
}

export class HotkeyMonitor {
  private triggerKeycode: number;
  private readonly handlers: HotkeyHandlers;

  private pendingSince = 0;
  private pendingTimer: NodeJS.Timeout | null = null;
  private activeSince = 0;
  private chordDetected = false;
  private running = false;

  constructor(triggerKeycode: number, handlers: HotkeyHandlers) {
    this.triggerKeycode = triggerKeycode;
    this.handlers = handlers;
  }

  setTrigger(keycode: number): void {
    this.reset();
    this.triggerKeycode = keycode;
  }

  start(): void {
    if (this.running) return;
    uIOhook.on('keydown', this.handleDown);
    uIOhook.on('keyup', this.handleUp);
    uIOhook.start();
    this.running = true;
  }

  stop(): void {
    if (!this.running) return;
    uIOhook.off('keydown', this.handleDown);
    uIOhook.off('keyup', this.handleUp);
    uIOhook.stop();
    this.reset();
    this.running = false;
  }

  private reset(): void {
    if (this.pendingTimer) clearTimeout(this.pendingTimer);
    this.pendingTimer = null;
    this.pendingSince = 0;
    this.activeSince = 0;
    this.chordDetected = false;
  }

  private handleDown = (event: { keycode: number }): void => {
    if (event.keycode === ESCAPE_KEYCODE) {
      this.handlers.onEscape();
      return;
    }

    if (event.keycode !== this.triggerKeycode) {
      // Any other key while the trigger is held makes it a chord, not dictation.
      if (this.pendingTimer) {
        clearTimeout(this.pendingTimer);
        this.pendingTimer = null;
        this.pendingSince = 0;
      }
      if (this.activeSince > 0) this.chordDetected = true;
      return;
    }

    // Auto-repeat, or a down we already know about.
    if (this.pendingSince > 0 || this.activeSince > 0) return;

    this.chordDetected = false;
    this.pendingSince = Date.now();
    this.pendingTimer = setTimeout(() => {
      this.pendingTimer = null;
      if (this.pendingSince === 0 || this.chordDetected) return;
      this.activeSince = this.pendingSince;
      this.pendingSince = 0;
      this.handlers.onPress();
    }, SOLO_HOLD_MS);
  };

  private handleUp = (event: { keycode: number }): void => {
    if (event.keycode !== this.triggerKeycode) return;

    // Released before it qualified as a hold: a fast tap. Report both halves
    // together so the caller can see it as one.
    if (this.pendingSince > 0) {
      const held = Date.now() - this.pendingSince;
      if (this.pendingTimer) clearTimeout(this.pendingTimer);
      this.pendingTimer = null;
      this.pendingSince = 0;
      if (this.chordDetected) return;
      this.handlers.onPress();
      this.handlers.onRelease(held);
      return;
    }

    if (this.activeSince === 0) return;
    const held = Date.now() - this.activeSince;
    this.activeSince = 0;
    this.handlers.onRelease(held);
  };
}

/** Listens for one key press and hands back its raw code, for the "press a key to
 *  set it" control in Settings. Raw codes differ between keyboards, so asking is
 *  more reliable than a table of guesses. */
export function captureNextKey(timeoutMs = 5000): Promise<{ keycode: number } | null> {
  return new Promise((resolve) => {
    let done = false;

    const finish = (result: { keycode: number } | null): void => {
      if (done) return;
      done = true;
      uIOhook.off('keydown', listener);
      clearTimeout(timer);
      resolve(result);
    };

    const listener = (event: { keycode: number }): void => finish({ keycode: event.keycode });
    const timer = setTimeout(() => finish(null), timeoutMs);

    uIOhook.on('keydown', listener);
  });
}
