import { BrowserWindow, ipcMain, app, session } from 'electron';
import fs from 'node:fs';
import path from 'node:path';

/// Microphone capture.
///
/// Recording happens in a hidden window rather than in the main process, because
/// Chromium's getUserMedia already does the hard parts: picking the default input,
/// resampling to 16 kHz, and handling a device that changes mid-take. Asking for a
/// 16 kHz mono AudioContext means the samples arrive in exactly the shape
/// whisper.cpp wants, so nothing has to be converted afterwards.

const SAMPLE_RATE = 16_000;

export class Recorder {
  private window: BrowserWindow | null = null;
  private chunks: Float32Array[] = [];
  private capturing = false;

  /** Highest level heard since the take started, so a take that caught nothing can
   *  be thrown away instead of transcribed into an invented word. */
  private heardSpeech = false;

  onLevel: ((level: number) => void) | null = null;

  /** Called when the microphone can't be opened, so the UI can say so instead of
   *  recording silence forever. */
  onFailure: ((message: string) => void) | null = null;

  async prepare(): Promise<void> {
    if (this.window) return;

    const window = new BrowserWindow({
      show: false,
      webPreferences: {
        preload: path.join(__dirname, 'preload.js'),
        nodeIntegration: false,
        contextIsolation: true,
      },
    });
    // Chromium asks before handing out the microphone, even to a local page, and a
    // request with no handler is refused outright. Grant it to the capture window
    // and nothing else: the panel and the overlay have no business with the mic.
    const capture = window.webContents.id;
    const allowed = (permission: string, id: number) => permission === 'media' && id === capture;

    session.defaultSession.setPermissionRequestHandler((contents, permission, callback) => {
      callback(allowed(permission, contents.id));
    });
    session.defaultSession.setPermissionCheckHandler((contents, permission) =>
      allowed(permission, contents?.id ?? -1)
    );

    await window.loadFile(path.join(__dirname, '..', '..', 'src', 'renderer', 'capture.html'));
    this.window = window;

    ipcMain.on('audio:chunk', (_event, samples: ArrayBuffer, level: number) => {
      if (!this.capturing) return;
      this.chunks.push(new Float32Array(samples));
      if (level > 0.06) this.heardSpeech = true;
      this.onLevel?.(level);
    });

    ipcMain.on('audio:failed', (_event, message: string) => {
      this.capturing = false;
      this.chunks = [];
      this.onFailure?.(message);
    });
  }

  start(): void {
    this.chunks = [];
    this.heardSpeech = false;
    this.capturing = true;
    this.window?.webContents.send('audio:start');
  }

  /** Returns the path of a 16 kHz mono WAV file, or null when the take was too
   *  short or never rose above the noise floor. */
  stop(): string | null {
    this.capturing = false;
    this.window?.webContents.send('audio:stop');

    const total = this.chunks.reduce((sum, chunk) => sum + chunk.length, 0);
    const chunks = this.chunks;
    this.chunks = [];

    // A quarter of a second, the same floor the Mac version uses.
    if (total < SAMPLE_RATE / 4 || !this.heardSpeech) return null;

    const samples = new Float32Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      samples.set(chunk, offset);
      offset += chunk.length;
    }

    const file = path.join(app.getPath('temp'), `freeflow-${Date.now()}.wav`);
    fs.writeFileSync(file, wav(samples));
    return file;
  }

  get durationSeconds(): number {
    return this.chunks.reduce((sum, chunk) => sum + chunk.length, 0) / SAMPLE_RATE;
  }
}

/** 16-bit PCM WAV. whisper.cpp reads this directly. */
function wav(samples: Float32Array): Buffer {
  const header = Buffer.alloc(44);
  const body = Buffer.alloc(samples.length * 2);

  for (let index = 0; index < samples.length; index += 1) {
    const sample = Math.max(-1, Math.min(1, samples[index] ?? 0));
    body.writeInt16LE(Math.round(sample * 32767), index * 2);
  }

  header.write('RIFF', 0);
  header.writeUInt32LE(36 + body.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16); // PCM header size
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(SAMPLE_RATE, 24);
  header.writeUInt32LE(SAMPLE_RATE * 2, 28); // byte rate
  header.writeUInt16LE(2, 32); // block align
  header.writeUInt16LE(16, 34); // bits per sample
  header.write('data', 36);
  header.writeUInt32LE(body.length, 40);

  return Buffer.concat([header, body]);
}
