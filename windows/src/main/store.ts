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

// MARK: - Vocabulary
//
// Words the model keeps getting wrong: names, products, acronyms. Applied to the
// transcript before cleanup, and also handed to the cleanup prompt so it knows the
// spelling you want.

export function vocabulary(): string[] {
  return readJson<{ terms: string[] }>('vocabulary.json', { terms: [] }).terms;
}

export function setVocabulary(terms: string[]): string[] {
  const cleaned = [...new Set(terms.map((term) => term.trim()).filter(Boolean))];
  writeJson('vocabulary.json', { terms: cleaned });
  return cleaned;
}

/** Case-insensitive whole-word replacement, so "kubernetes" becomes "Kubernetes"
 *  without touching a longer word that happens to contain it. */
export function applyVocabulary(text: string): string {
  let output = text;
  for (const term of vocabulary()) {
    const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    output = output.replace(new RegExp(`\\b${escaped}\\b`, 'gi'), term);
  }
  return output;
}

// MARK: - Snippets

export interface Snippet {
  id: string;
  trigger: string;
  expansion: string;
  enabled: boolean;
}

export function snippets(): Snippet[] {
  return readJson<{ items: Snippet[] }>('snippets.json', { items: [] }).items;
}

export function setSnippets(items: Snippet[]): Snippet[] {
  writeJson('snippets.json', { items });
  return items;
}

/** Expanded before cleanup runs, so the inserted paragraph still gets shaped for
 *  wherever it is going. */
export function applySnippets(text: string): string {
  let output = text;
  for (const snippet of snippets()) {
    if (!snippet.enabled || !snippet.trigger.trim()) continue;
    const escaped = snippet.trigger.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    output = output.replace(new RegExp(`\\b${escaped}\\b`, 'gi'), snippet.expansion);
  }
  return output;
}

// MARK: - Actions

export interface Action {
  id: string;
  name: string;
  icon: string;
  prompt: string;
}

const DEFAULT_ACTIONS: Action[] = [
  {
    id: 'shorten',
    name: 'Shorten',
    icon: 'minimize',
    prompt: 'Make this significantly shorter while keeping every important point. Same voice, same meaning.',
  },
  {
    id: 'formal',
    name: 'Formal',
    icon: 'briefcase',
    prompt: "Rewrite this in a professional register. No slang or contractions, but don't make it stiff or corporate.",
  },
  {
    id: 'friendly',
    name: 'Friendly',
    icon: 'smile',
    prompt: 'Rewrite this to sound warm and conversational, like a message to a colleague you like.',
  },
  {
    id: 'bullets',
    name: 'Bullets',
    icon: 'list',
    prompt: 'Turn this into a tight bulleted list. One idea per bullet, no filler.',
  },
  {
    id: 'grammar',
    name: 'Fix grammar',
    icon: 'check',
    prompt: 'Fix grammar, spelling and punctuation only. Change nothing else about the wording.',
  },
  {
    id: 'summarize',
    name: 'Summarize',
    icon: 'align',
    prompt: 'Summarize this in two or three sentences, capturing the decisions and takeaways.',
  },
];

export function actions(): Action[] {
  return readJson<{ items: Action[] }>('actions.json', { items: DEFAULT_ACTIONS }).items;
}

export function setActions(items: Action[]): Action[] {
  writeJson('actions.json', { items });
  return items;
}

// MARK: - Style
//
// Per-app rules for how it writes. The Mac version matches on bundle identifiers;
// Windows has no equivalent, so these match on executable name.

export interface StyleRule {
  id: string;
  name: string;
  processes: string[];
  instruction: string;
  enabled: boolean;
  builtIn: boolean;
}

const DEFAULT_STYLE: StyleRule[] = [
  {
    id: 'chat',
    name: 'Chat',
    processes: ['slack', 'discord', 'teams', 'ms-teams', 'telegram', 'whatsapp'],
    instruction:
      'Keep it short and conversational, the way people actually type in chat. No greeting or sign-off.',
    enabled: true,
    builtIn: true,
  },
  {
    id: 'email',
    name: 'Email',
    processes: ['outlook', 'thunderbird', 'mailspring', 'em client'],
    instruction: 'Write clear, professional email prose with sensible paragraph breaks.',
    enabled: true,
    builtIn: true,
  },
  {
    id: 'code',
    name: 'Code',
    processes: ['code', 'devenv', 'idea64', 'pycharm64', 'sublime_text', 'windowsterminal', 'cursor'],
    instruction:
      'This is going into a code editor or terminal. Keep it terse and technical. No pleasantries.',
    enabled: true,
    builtIn: true,
  },
  {
    id: 'docs',
    name: 'Documents',
    processes: ['winword', 'notion', 'obsidian', 'onenote', 'notepad'],
    instruction: 'Write in full prose with proper paragraphs, the way it would read in a document.',
    enabled: true,
    builtIn: true,
  },
];

export function styleRules(): StyleRule[] {
  return readJson<{ items: StyleRule[] }>('style.json', { items: DEFAULT_STYLE }).items;
}

export function setStyleRules(items: StyleRule[]): StyleRule[] {
  writeJson('style.json', { items });
  return items;
}

/** The instruction for whichever rule matches the app being dictated into. */
export function styleFor(processName: string): string | null {
  const needle = processName.toLowerCase().replace(/\.exe$/, '');
  if (!needle) return null;
  for (const rule of styleRules()) {
    if (!rule.enabled) continue;
    if (rule.processes.some((name) => needle.includes(name.toLowerCase()))) return rule.instruction;
  }
  return null;
}

// MARK: - Insights
//
// Per-day totals, kept separately from the running stats so the chart has
// something to draw and a cleared history doesn't erase the record.

export interface DayRecord {
  date: string;
  words: number;
  dictations: number;
  seconds: number;
  apps: Record<string, number>;
}

export function days(): DayRecord[] {
  return readJson<{ items: DayRecord[] }>('insights.json', { items: [] }).items;
}

export function recordDay(text: string, seconds: number, appName: string): void {
  const date = new Date().toISOString().slice(0, 10);
  const words = text.trim().split(/\s+/).filter(Boolean).length;
  const items = days();
  const existing = items.find((day) => day.date === date);

  if (existing) {
    existing.words += words;
    existing.dictations += 1;
    existing.seconds += seconds;
    existing.apps[appName] = (existing.apps[appName] ?? 0) + words;
  } else {
    items.push({ date, words, dictations: 1, seconds, apps: { [appName]: words } });
  }

  // A year is plenty for a chart, and keeps the file small.
  writeJson('insights.json', { items: items.slice(-366) });
}
