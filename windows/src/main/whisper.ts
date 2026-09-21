import { app } from 'electron';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import https from 'node:https';
import type { ModelName } from './store';

/// Speech to text, on this machine, through whisper.cpp.
///
/// The binary is downloaded on first run rather than committed, the same way the
/// Mac version downloads its model. There is no Vulkan build published for Windows
/// x64, so the choice is CPU (20MB, works everywhere) or CUDA (643MB, NVIDIA only).

/// Pinned. Release tags move; this exact build is known to publish x64 binaries.
const BUILD = 'b5130';
const RELEASE = `https://github.com/ggml-org/whisper.cpp/releases/download/${BUILD}`;

const BINARIES = {
  cpu: 'whisper-blas-bin-x64.zip',
  cuda: 'whisper-cublas-12.4.0-bin-x64.zip',
} as const;

const MODEL_HOST = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

export interface Progress {
  stage: 'binary' | 'model' | 'ready';
  fraction: number;
  detail: string;
}

export type ProgressHandler = (progress: Progress) => void;

/** Electron's userData, unless something set FREEFLOW_DATA_DIR. The override is
 *  what lets the smoke test drive this file on a CI runner with no Electron. */
function dataRoot(): string {
  return process.env.FREEFLOW_DATA_DIR ?? app.getPath('userData');
}

function supportDir(name: string): string {
  const dir = path.join(dataRoot(), name);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

// MARK: - Downloading

function download(url: string, destination: string, onProgress: (fraction: number) => void): Promise<void> {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(destination);

    const get = (target: string, redirects = 0): void => {
      https
        .get(target, { headers: { 'User-Agent': 'FreeFlow' } }, (response) => {
          const status = response.statusCode ?? 0;
          const location = response.headers.location;

          // Both GitHub releases and Hugging Face answer with a redirect to a CDN.
          if (status >= 300 && status < 400 && location) {
            if (redirects > 5) {
              reject(new Error('Too many redirects'));
              return;
            }
            response.resume();
            get(new URL(location, target).toString(), redirects + 1);
            return;
          }

          if (status !== 200) {
            response.resume();
            reject(new Error(`Download failed with HTTP ${status}`));
            return;
          }

          const total = Number(response.headers['content-length'] ?? 0);
          let received = 0;
          response.on('data', (chunk: Buffer) => {
            received += chunk.length;
            if (total > 0) onProgress(received / total);
          });
          response.pipe(file);
          file.on('finish', () => file.close(() => resolve()));
        })
        .on('error', reject);
    };

    file.on('error', reject);
    get(url);
  });
}

/** Windows ships Expand-Archive, so unzipping needs no dependency. */
function unzip(zip: string, destination: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      'powershell.exe',
      [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        `Expand-Archive -LiteralPath '${zip}' -DestinationPath '${destination}' -Force`,
      ],
      { windowsHide: true }
    );
    child.on('error', reject);
    child.on('exit', (code) =>
      code === 0 ? resolve() : reject(new Error(`Expand-Archive exited with ${code}`))
    );
  });
}

// MARK: - Binary

/** The executable is called whisper-cli.exe in current builds and main.exe in
 *  older ones, and sits at a different depth depending on the zip.
 *
 *  Order matters and is the whole point of this function. Current builds ship
 *  both names, but their main.exe is a stub that prints "the binary 'main.exe'
 *  is deprecated" and exits 1 without transcribing anything. Taking whichever
 *  turned up first in the directory listing meant taking main.exe, because m
 *  sorts before w. */
function findExecutable(root: string): string | null {
  const preference = ['whisper-cli.exe', 'main.exe'];
  const found = new Map<string, string>();
  const queue = [root];

  while (queue.length > 0) {
    const dir = queue.shift();
    if (!dir) break;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      const name = entry.name.toLowerCase();
      if (entry.isDirectory()) queue.push(full);
      else if (preference.includes(name) && !found.has(name)) found.set(name, full);
    }
  }

  for (const name of preference) {
    const match = found.get(name);
    if (match) return match;
  }
  return null;
}

async function ensureBinary(useCuda: boolean, onProgress: ProgressHandler): Promise<string> {
  const dir = supportDir(path.join('whisper', useCuda ? 'cuda' : 'cpu'));
  const existing = findExecutable(dir);
  if (existing) return existing;

  const asset = useCuda ? BINARIES.cuda : BINARIES.cpu;
  const zip = path.join(dir, asset);

  onProgress({ stage: 'binary', fraction: 0, detail: 'Downloading the speech engine' });
  await download(`${RELEASE}/${asset}`, zip, (fraction) =>
    onProgress({ stage: 'binary', fraction, detail: 'Downloading the speech engine' })
  );
  await unzip(zip, dir);
  fs.rmSync(zip, { force: true });

  const executable = findExecutable(dir);
  if (!executable) throw new Error('The speech engine downloaded but no executable was found in it');
  return executable;
}

// MARK: - Model

async function ensureModel(model: ModelName, onProgress: ProgressHandler): Promise<string> {
  const dir = supportDir('models');
  const file = path.join(dir, `ggml-${model}.bin`);
  if (fs.existsSync(file) && fs.statSync(file).size > 1_000_000) return file;

  onProgress({ stage: 'model', fraction: 0, detail: `Downloading ${model}` });
  const partial = `${file}.part`;
  await download(`${MODEL_HOST}/ggml-${model}.bin`, partial, (fraction) =>
    onProgress({ stage: 'model', fraction, detail: `Downloading ${model}` })
  );
  fs.renameSync(partial, file);
  return file;
}

// MARK: - Transcribing

let cached: { executable: string; model: string; name: ModelName; cuda: boolean } | null = null;

export async function prepare(
  model: ModelName,
  useCuda: boolean,
  onProgress: ProgressHandler
): Promise<void> {
  if (cached && cached.name === model && cached.cuda === useCuda) return;
  const executable = await ensureBinary(useCuda, onProgress);
  const modelPath = await ensureModel(model, onProgress);
  cached = { executable, model: modelPath, name: model, cuda: useCuda };
  onProgress({ stage: 'ready', fraction: 1, detail: 'Ready' });
}

export function isReady(): boolean {
  return cached !== null;
}

/** Runs whisper.cpp over a 16 kHz mono WAV file and returns what it heard. */
export function transcribe(wavPath: string): Promise<string> {
  const ready = cached;
  if (!ready) return Promise.reject(new Error('The speech model is not loaded yet'));

  return new Promise((resolve, reject) => {
    const threads = Math.max(2, Math.min(8, require('node:os').cpus().length - 2));
    const child = spawn(
      ready.executable,
      ['-m', ready.model, '-f', wavPath, '-l', 'en', '-nt', '-t', String(threads)],
      { windowsHide: true }
    );

    let out = '';
    let errors = '';
    child.stdout.on('data', (chunk: Buffer) => (out += chunk.toString()));
    child.stderr.on('data', (chunk: Buffer) => (errors += chunk.toString()));
    child.on('error', (error) => reject(new Error(`Could not start the speech engine: ${error.message}`)));
    child.on('exit', (code) => {
      if (code !== 0) {
        // "exited with 1" on its own tells nobody anything. whisper.cpp puts its
        // real complaint on stderr, and a missing DLL kills it before it writes
        // any, so the command itself is part of the message.
        const said = [errors, out]
          .map((stream) => stream.trim())
          .filter(Boolean)
          .join('\n')
          .split('\n')
          .filter((line) => line.trim().length > 0)
          .slice(-6)
          .join('\n');

        reject(
          new Error(
            said || `The speech engine exited with code ${code} and said nothing. Ran: ${ready.executable}`
          )
        );
        return;
      }
      resolve(out.replace(/\s+/g, ' ').trim());
    });
  });
}

/// What Whisper produces from breath, room noise or a clipped syllable. Only
/// dropped when it is the entire transcript, so real words are never touched.
const SILENCE_ARTIFACTS = new Set([
  'uh', 'um', 'umm', 'hmm', 'mm', 'mhm', 'you',
  'blankaudio', 'silence', 'inaudible', 'music', 'thanks', '',
]);

export function isSilenceArtifact(text: string): boolean {
  const words = text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, '')
    .split(/\s+/)
    .filter(Boolean);
  return words.length === 0 || words.every((word) => SILENCE_ARTIFACTS.has(word));
}
