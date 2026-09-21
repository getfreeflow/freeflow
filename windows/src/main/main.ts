import { app, BrowserWindow, Tray, Menu, ipcMain, screen, shell, nativeImage, nativeTheme } from 'electron';
import fs from 'node:fs';
import path from 'node:path';
import * as store from './store';
import * as whisper from './whisper';
import * as groq from './groq';
import * as inject from './inject';
import * as foreground from './foreground';
import { cleanupSystemPrompt } from './prompts';
import { Recorder } from './audio';
import { HotkeyMonitor, captureNextKey } from './hotkey';

/// Owns the whole pipeline and the state the windows render.
///
///   hold key → record → transcribe (on this machine) → clean up → insert
///
/// Hold to talk; letting go inserts. Double-tap to lock recording on, then one more
/// tap, or the tick, stops it. A single stray tap does nothing. Recording starts on
/// the first press either way, so a hold loses nothing to waiting and a double tap
/// keeps the audio from its first tap.

type Phase = 'idle' | 'preparing' | 'recording' | 'transcribing' | 'polishing' | 'failed';
type Outcome = 'inserted' | 'copied' | 'discarded';

const RENDERER = path.join(__dirname, '..', '..', 'src', 'renderer');
const ASSETS = path.join(__dirname, '..', '..', 'assets');

/// A press shorter than this is a tap, not a hold.
const TAP_MAX_MS = 300;
/// How long after a first tap a second one still counts.
const DOUBLE_TAP_MS = 450;
/// A locked take that has heard nothing is abandoned after this long.
const SILENT_LATCH_MS = 15_000;

let overlay: BrowserWindow | null = null;
let panel: BrowserWindow | null = null;
let main: BrowserWindow | null = null;
let tray: Tray | null = null;
/// Set on the way out, so closing the window hides it but quitting really quits.
let quitting = false;
let hotkey: HotkeyMonitor | null = null;

const recorder = new Recorder();

let phase: Phase = 'idle';
let outcome: Outcome = 'inserted';
let level = 0;
let statusMessage = '';
let latched = false;
let awaitingSecondTap = false;
let ignoreNextRelease = false;
let secondTapTimer: NodeJS.Timeout | null = null;
let latchWatchdog: NodeJS.Timeout | null = null;
let hideOverlayTimer: NodeJS.Timeout | null = null;
let startedAt = 0;
let targetApp: Promise<foreground.ForegroundApp> = Promise.resolve({ process: '', name: 'Windows' });

// MARK: - Windows

function topCentre(width: number, height: number): Electron.Rectangle {
  const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  return {
    x: Math.round(display.bounds.x + (display.bounds.width - width) / 2),
    y: display.bounds.y,
    width,
    height,
  };
}

function createOverlay(): void {
  const bounds = topCentre(380, 130);
  overlay = new BrowserWindow({
    ...bounds,
    frame: false,
    transparent: true,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    skipTaskbar: true,
    focusable: false,
    hasShadow: false,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
    },
  });

  // Above full-screen windows, and on every virtual desktop.
  overlay.setAlwaysOnTop(true, 'screen-saver');
  overlay.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  // Clicks pass through unless the overlay has buttons on it.
  overlay.setIgnoreMouseEvents(true, { forward: true });
  void overlay.loadFile(path.join(RENDERER, 'overlay.html'));
}

/// The app itself: a normal window with a taskbar button, an Alt-Tab entry and a
/// Start Menu shortcut. The tray panel is a glance; this is where the history,
/// insights, vocabulary and settings live.
///
/// Closing it hides it rather than quitting, because the trigger key has to keep
/// working with no window open. Quit is on the tray menu and inside the app.
function createMainWindow(): void {
  main = new BrowserWindow({
    width: 1040,
    height: 720,
    minWidth: 860,
    minHeight: 560,
    show: false,
    title: 'FreeFlow',
    icon: path.join(ASSETS, 'icon.ico'),
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#0f0f10' : '#f6f6f7',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
    },
  });

  void main.loadFile(path.join(RENDERER, 'app.html'));

  main.on('close', (event) => {
    if (quitting) return;
    event.preventDefault();
    main?.hide();
  });

  nativeTheme.on('updated', () => {
    main?.webContents.send('theme', nativeTheme.shouldUseDarkColors ? 'dark' : 'light');
  });
}

function showMain(): void {
  if (!main) return;
  if (main.isMinimized()) main.restore();
  main.show();
  main.focus();
  broadcast();
}

function createPanel(): void {
  panel = new BrowserWindow({
    ...topCentre(508, 640),
    frame: false,
    transparent: true,
    resizable: false,
    movable: false,
    skipTaskbar: true,
    hasShadow: false,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
    },
  });
  panel.setAlwaysOnTop(true, 'pop-up-menu');
  void panel.loadFile(path.join(RENDERER, 'panel.html'));

  // Clicking anywhere else closes it, the way a menu does.
  panel.on('blur', () => hidePanel());
}

function showPanel(): void {
  if (!panel) return;
  panel.setBounds(topCentre(508, 640));
  panel.showInactive();
  panel.focus();
  panel.webContents.send('panel:open');
  broadcast();
}

function hidePanel(): void {
  if (!panel?.isVisible()) return;
  panel.webContents.send('panel:close');
  // Let the collapse animation run before the window goes.
  setTimeout(() => panel?.hide(), 260);
}

function showOverlay(): void {
  if (!store.settings().showOverlay || !overlay) return;
  if (hideOverlayTimer) clearTimeout(hideOverlayTimer);
  if (!overlay.isVisible()) {
    overlay.setBounds(topCentre(380, 130));
    overlay.showInactive();
  }
  overlay.webContents.send('overlay:show');
}

function scheduleOverlayHide(delay = 900): void {
  if (hideOverlayTimer) clearTimeout(hideOverlayTimer);
  hideOverlayTimer = setTimeout(() => {
    if (phase === 'recording') return;
    overlay?.webContents.send('overlay:hide');
    setTimeout(() => {
      if (phase !== 'recording') overlay?.hide();
    }, 300);
  }, delay);
}

function hideOverlayNow(): void {
  if (hideOverlayTimer) clearTimeout(hideOverlayTimer);
  overlay?.webContents.send('overlay:hide');
  setTimeout(() => {
    if (phase !== 'recording') overlay?.hide();
  }, 300);
}

/** Everything the windows draw from. Sent on every change rather than diffed: it is
 *  a handful of fields and this way the two windows can never disagree. */
function snapshot(): object {
  const settings = store.settings();
  return {
    phase,
    latched,
    level,
    outcome,
    statusMessage,
    modelReady: whisper.isReady(),
    hasKey: store.apiKey().length > 0,
    theme: nativeTheme.shouldUseDarkColors ? 'dark' : 'light',
    settings,
    stats: store.stats(),
    history: store.history().slice(0, 200),
    vocabulary: store.vocabulary(),
    snippets: store.snippets(),
    actions: store.actions(),
    style: store.styleRules(),
    days: store.days(),
  };
}

function broadcast(): void {
  const state = snapshot();
  overlay?.webContents.send('state', state);
  if (panel?.isVisible()) panel.webContents.send('state', state);
  if (main && !main.isDestroyed()) main.webContents.send('state', state);
}

// MARK: - Trigger handling

function triggerDown(): void {
  if (phase === 'recording') {
    if (latched) {
      void finish(true); // a tap while locked ends the take
    } else if (awaitingSecondTap) {
      latch();
    }
    return;
  }
  if (phase === 'transcribing' || phase === 'polishing') return;
  void beginRecording();
}

function triggerUp(heldMs: number): void {
  if (phase !== 'recording') return;
  if (ignoreNextRelease) {
    ignoreNextRelease = false;
    return;
  }
  if (latched) return;

  if (heldMs < TAP_MAX_MS) {
    // Maybe the first half of a double tap. Keep recording, and give up if no
    // second tap arrives.
    awaitingSecondTap = true;
    if (secondTapTimer) clearTimeout(secondTapTimer);
    secondTapTimer = setTimeout(() => {
      if (!awaitingSecondTap) return;
      awaitingSecondTap = false;
      discardTake();
    }, DOUBLE_TAP_MS);
  } else {
    void finish(true);
  }
}

function latch(): void {
  cancelSecondTapWait();
  latched = true;
  ignoreNextRelease = true;
  overlay?.setIgnoreMouseEvents(false);
  if (latchWatchdog) clearTimeout(latchWatchdog);
  latchWatchdog = setTimeout(() => {
    // Never heard anything, which is what an accidental double tap looks like.
    if (phase === 'recording' && latched) discardTake();
  }, SILENT_LATCH_MS);
  broadcast();
}

function cancelSecondTapWait(): void {
  awaitingSecondTap = false;
  if (secondTapTimer) clearTimeout(secondTapTimer);
  secondTapTimer = null;
}

function resetTakeState(): void {
  cancelSecondTapWait();
  if (latchWatchdog) clearTimeout(latchWatchdog);
  latchWatchdog = null;
  latched = false;
  ignoreNextRelease = false;
  level = 0;
  overlay?.setIgnoreMouseEvents(true, { forward: true });
}

async function beginRecording(): Promise<void> {
  if (!whisper.isReady()) {
    statusMessage = 'The speech model is still downloading';
    phase = 'failed';
    showOverlay();
    broadcast();
    scheduleOverlayHide(2500);
    return;
  }

  phase = 'recording';
  statusMessage = '';
  startedAt = Date.now();
  resetTakeState();
  // Asked for now, awaited later, so the mic starts without waiting on PowerShell.
  targetApp = foreground.foregroundApp();
  recorder.start();
  showOverlay();
  broadcast();
}

function discardTake(): void {
  if (phase !== 'recording') return;
  recorder.stop();
  resetTakeState();
  phase = 'idle';
  broadcast();
  hideOverlayNow();
}

async function finish(insert: boolean): Promise<void> {
  const file = recorder.stop();
  resetTakeState();
  // Out of 'recording' now, so presses during the stop are ignored.
  phase = 'transcribing';
  broadcast();
  if (store.settings().playSounds) shell.beep();

  // Too short, or nothing ever rose above the noise floor. Whisper handed silence
  // doesn't return nothing, it invents a word.
  if (!file) {
    phase = 'idle';
    broadcast();
    hideOverlayNow();
    return;
  }

  const seconds = (Date.now() - startedAt) / 1000;

  try {
    const raw = await whisper.transcribe(file);
    fs.rmSync(file, { force: true });

    if (whisper.isSilenceArtifact(raw)) {
      phase = 'idle';
      broadcast();
      hideOverlayNow();
      return;
    }

    const where = await targetApp;

    // Vocabulary and snippets are applied to the raw transcript, before cleanup,
    // so the model shapes the expanded text rather than the trigger word.
    let text = store.applySnippets(store.applyVocabulary(raw));

    const key = store.apiKey();
    if (store.settings().cleanupEnabled && key) {
      phase = 'polishing';
      broadcast();
      try {
        text = await groq.complete(
          key,
          store.settings().groqModel,
          cleanupSystemPrompt(where.process, where.name, {
            style: store.styleFor(where.process),
            vocabulary: store.vocabulary(),
          }),
          text
        );
      } catch (error) {
        // Never lose a dictation to a cleanup failure. Keep the raw transcript and
        // say why it wasn't polished.
        statusMessage = error instanceof Error ? error.message : 'Cleanup failed';
      }
    }

    // Recorded either way. Declining to insert shouldn't lose the take.
    store.addHistory(text, where.name);

    if (!insert) {
      outcome = 'discarded';
      phase = 'idle';
      broadcast();
      scheduleOverlayHide(1400);
      return;
    }

    outcome = (await inject.insert(text)) === 'pasted' ? 'inserted' : 'copied';
    store.recordStats(text, seconds);
    store.recordDay(text, seconds, where.name);
    phase = 'idle';
    broadcast();
    scheduleOverlayHide(outcome === 'copied' ? 1800 : 900);
  } catch (error) {
    fs.rmSync(file, { force: true });
    statusMessage = error instanceof Error ? error.message : 'Transcription failed';
    phase = 'failed';
    broadcast();
    scheduleOverlayHide(2600);
  }
}

// MARK: - Model

async function prepareModel(): Promise<void> {
  const settings = store.settings();
  phase = 'preparing';
  broadcast();
  try {
    await whisper.prepare(settings.model, settings.useCuda, (progress) => {
      statusMessage =
        progress.stage === 'ready'
          ? ''
          : `${progress.detail}, ${Math.round(progress.fraction * 100)}%`;
      broadcast();
    });
    phase = 'idle';
    statusMessage = '';
  } catch (error) {
    phase = 'failed';
    statusMessage = error instanceof Error ? error.message : 'The speech engine failed to set up';
  }
  broadcast();
}

// MARK: - Tray

function trayIcon(): Electron.NativeImage {
  // The taskbar is dark under the dark theme and light under the light one, and
  // a white mark vanishes on a light taskbar. shouldUseDarkColors follows the app
  // theme rather than the taskbar's, which are separate settings in Windows, but
  // it is right far more often than a fixed choice would be.
  const name = nativeTheme.shouldUseDarkColors ? 'tray.png' : 'tray-light.png';
  const file = path.join(ASSETS, name);
  return fs.existsSync(file) ? nativeImage.createFromPath(file) : nativeImage.createEmpty();
}

function createTray(): void {
  tray = new Tray(trayIcon());
  tray.setToolTip('FreeFlow');

  // Left click drops the panel from the top of the screen, the way clicking the
  // menu bar does on a Mac. Right click is the Windows convention for a menu.
  tray.on('click', () => (panel?.isVisible() ? hidePanel() : showPanel()));
  tray.on('double-click', () => showMain());

  const menu = Menu.buildFromTemplate([
    { label: 'Open FreeFlow', click: () => showMain() },
    { label: 'Quick panel', click: () => (panel?.isVisible() ? hidePanel() : showPanel()) },
    { type: 'separator' },
    { label: 'Your data folder', click: () => void shell.openPath(app.getPath('userData')) },
    { type: 'separator' },
    { label: 'Quit FreeFlow', click: () => app.quit() },
  ]);
  tray.setContextMenu(menu);

  nativeTheme.on('updated', () => tray?.setImage(trayIcon()));
}

// MARK: - IPC

function registerIpc(): void {
  ipcMain.on('overlay:accept', () => {
    if (phase === 'recording') void finish(true);
  });
  ipcMain.on('overlay:discard', () => {
    if (phase === 'recording') void finish(false);
  });
  ipcMain.on('panel:hide', () => hidePanel());
  ipcMain.on('panel:quit', () => app.quit());

  ipcMain.handle('state:get', () => snapshot());

  ipcMain.handle('settings:set', async (_event, changes: Partial<store.Settings>) => {
    const before = store.settings();
    const after = store.updateSettings(changes);
    if (changes.triggerKeycode !== undefined) hotkey?.setTrigger(after.triggerKeycode);
    if (changes.model !== undefined && changes.model !== before.model) void prepareModel();
    if (changes.useCuda !== undefined && changes.useCuda !== before.useCuda) void prepareModel();
    broadcast();
    return snapshot();
  });

  ipcMain.handle('key:set', (_event, key: string) => {
    store.setApiKey(key);
    broadcast();
    return snapshot();
  });

  /** The Settings control asks the user to press a key and stores whatever arrives,
   *  because raw key codes differ between keyboards. */
  ipcMain.handle('trigger:capture', async () => {
    const captured = await captureNextKey();
    if (!captured) return null;
    return captured.keycode;
  });

  ipcMain.handle('history:update', (_event, entries: store.HistoryEntry[]) => {
    store.updateHistory(entries);
    broadcast();
    return snapshot();
  });

  ipcMain.handle('folder:open', () => shell.openPath(app.getPath('userData')));

  // The screens in the main window. Each one reads a collection and writes it
  // back whole: these are tens of rows, not thousands, and a whole-list write
  // cannot leave two halves disagreeing.
  ipcMain.handle('vocabulary:set', (_event, terms: string[]) => {
    store.setVocabulary(terms);
    broadcast();
    return snapshot();
  });

  ipcMain.handle('snippets:set', (_event, items: store.Snippet[]) => {
    store.setSnippets(items);
    broadcast();
    return snapshot();
  });

  ipcMain.handle('actions:set', (_event, items: store.Action[]) => {
    store.setActions(items);
    broadcast();
    return snapshot();
  });

  ipcMain.handle('style:set', (_event, items: store.StyleRule[]) => {
    store.setStyleRules(items);
    broadcast();
    return snapshot();
  });

  ipcMain.on('window:show', () => showMain());
  ipcMain.on('window:minimize', () => main?.minimize());
  ipcMain.on('window:close', () => main?.hide());
}

// MARK: - Lifecycle

app.setName('FreeFlow');

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => showMain());

  void app.whenReady().then(async () => {
    // A tray app, so no Dock or taskbar presence of its own.
    app.setLoginItemSettings({ openAtLogin: false });

    registerIpc();
    createOverlay();
    createPanel();
    createMainWindow();
    createTray();

    inject.warmUp();
    foreground.warmUp();
    await recorder.prepare();
    recorder.onLevel = (value) => {
      level = value;
      overlay?.webContents.send('level', value);
    };
    recorder.onFailure = (message) => {
      resetTakeState();
      statusMessage = message;
      phase = 'failed';
      showOverlay();
      broadcast();
      scheduleOverlayHide(3000);
    };

    const settings = store.settings();
    hotkey = new HotkeyMonitor(settings.triggerKeycode, {
      onPress: () => triggerDown(),
      onRelease: (heldMs) => triggerUp(heldMs),
      onEscape: () => discardTake(),
    });
    hotkey.start();

    void prepareModel();
    // First run opens the app so there is something to look at while the model
    // downloads. After that it starts quietly in the tray.
    if (!settings.hasOnboarded) showMain();
  });

  app.on('window-all-closed', () => {
    // Closing the panel shouldn't quit. FreeFlow keeps listening from the tray.
  });

  app.on('before-quit', () => {
    quitting = true;
    hotkey?.stop();
    inject.shutdown();
    foreground.shutdown();
  });
}
