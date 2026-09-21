import { app } from 'electron';
import fs from 'node:fs';
import path from 'node:path';

/// Everything FreeFlow keeps lives in %APPDATA%\FreeFlow as plain JSON, the same
/// shapes the Mac version uses. Nothing is sent anywhere.

export type ModelName = 'base.en' | 'small.en' | 'large-v3-turbo-q5_0';

export interface Settings {
  /** uiohook keycode of the trigger key. Captured by pressing the key in Settings,
   *  because raw codes differ between keyboards and guessing them is how hotkeys
   *  end up dead. */
  triggerKeycode: number;
  triggerLabel: string;
  model: ModelName;
  /** Use the CUDA build of whisper.cpp. Only worth it on an NVIDIA card, and it's
   *  a 643MB download, so it's off unless asked for. */
  useCuda: boolean;
  cleanupEnabled: boolean;
  groqModel: string;
  showOverlay: boolean;
  playSounds: boolean;
  hasOnboarded: boolean;
}

export interface HistoryEntry {
  id: string;
  text: string;
  app: string;
  at: string;
  pinned: boolean;
}

export interface Stats {
  totalWords: number;
  totalDictations: number;
  totalSeconds: number;
}

const DEFAULT_SETTINGS: Settings = {
  // Right Alt, the closest thing to the Mac build's Right Option. Re-bindable.
  triggerKeycode: 3640,
  triggerLabel: 'Right Alt',
  // Not the large model. Windows transcribes on the CPU, where large is slow
  // enough to notice on every take.
  model: 'small.en',
  useCuda: false,
  cleanupEnabled: true,
  groqModel: 'llama-3.3-70b-versatile',
  showOverlay: true,
  playSounds: true,
  hasOnboarded: false,
};

function dataDir(): string {
  const dir = app.getPath('userData');
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function filePath(name: string): string {
  return path.join(dataDir(), name);
}

function readJson<T>(name: string, fallback: T): T {
  try {
    const raw = fs.readFileSync(filePath(name), 'utf8');
    return { ...fallback, ...(JSON.parse(raw) as object) } as T;
  } catch {
    return fallback;
  }
}

/** Written to a sibling file first so a crash mid-write can't leave a truncated
 *  file where the settings used to be. */
function writeJson(name: string, value: unknown): void {
  const target = filePath(name);
  const temporary = `${target}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2), 'utf8');
  fs.renameSync(temporary, target);
}

// MARK: - Settings

let cachedSettings: Settings | null = null;

export function settings(): Settings {
  cachedSettings ??= readJson('settings.json', DEFAULT_SETTINGS);
  return cachedSettings;
}

export function updateSettings(changes: Partial<Settings>): Settings {
  cachedSettings = { ...settings(), ...changes };
  writeJson('settings.json', cachedSettings);
  return cachedSettings;
}

// MARK: - API key
//
// Kept out of settings.json so it's obvious what holds a credential. It is not
// encrypted: any program running as you can read it. Documented in the README
// rather than dressed up.

export function apiKey(): string {
  return readJson<{ groq: string }>('credentials.json', { groq: '' }).groq.trim();
}

export function setApiKey(key: string): void {
  writeJson('credentials.json', { groq: key.trim() });
}

// MARK: - History

const HISTORY_LIMIT = 200;

export function history(): HistoryEntry[] {
  return readJson<{ entries: HistoryEntry[] }>('history.json', { entries: [] }).entries;
}

export function addHistory(text: string, appName: string): HistoryEntry {
  const entry: HistoryEntry = {
    id: crypto.randomUUID(),
    text,
    app: appName,
    at: new Date().toISOString(),
    pinned: false,
  };
  const entries = [entry, ...history()];
  // Pinned entries survive the cull, everything else falls off the end.
  const kept = entries.filter((e) => e.pinned).concat(entries.filter((e) => !e.pinned));
  writeJson('history.json', { entries: kept.slice(0, HISTORY_LIMIT) });
  return entry;
}

export function updateHistory(entries: HistoryEntry[]): void {
  writeJson('history.json', { entries });
}

// MARK: - Stats

export function stats(): Stats {
  return readJson<Stats>('stats.json', { totalWords: 0, totalDictations: 0, totalSeconds: 0 });
}

export function recordStats(text: string, seconds: number): Stats {
  const current = stats();
  const updated: Stats = {
    totalWords: current.totalWords + text.trim().split(/\s+/).filter(Boolean).length,
    totalDictations: current.totalDictations + 1,
    totalSeconds: current.totalSeconds + seconds,
  };
  writeJson('stats.json', updated);
  return updated;
}
