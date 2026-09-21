# FreeFlow for Windows

Hold a key, talk, and the text appears wherever your cursor is. Same idea as the
macOS build in the parent folder, rebuilt on Electron so it runs on Windows 10 and 11
(x64).

Speech to text runs on your machine with whisper.cpp. The only thing that leaves the
computer is the optional cleanup pass, which sends the raw transcript to Groq using
your own API key. Turn that off and nothing goes anywhere.

## What it does

- Hold the trigger key (Right Alt by default) and talk. Let go and the text is pasted
  into the app you were in.
- Double-tap the trigger key to lock recording on. Tap again to finish.
- Press Esc while recording to throw the take away.
- A small panel drops out of the top centre of the screen while you talk, with a live
  level meter. It is the Windows stand-in for the Mac build's notch overlay.
- Click the tray icon for a quick panel, or open the app for everything else.

The app window has Dashboard, History, Insights, Vocabulary, Snippets, Actions, Style
and Settings, and follows the Windows light or dark theme.

**Meetings is not ported.** On the Mac, FreeFlow can record both sides of a call from
the system's audio output and write it up. That is Mac-only. Everything else is here.

## Requirements

- Windows 10 or 11, 64-bit
- Node.js 20 or newer, to build it
- About 1GB of disk for the speech model and the whisper.cpp binary, both downloaded
  on first run
- A Groq API key, if you want the cleanup pass. The free tier is enough.

## Build and run

```bash
cd windows
npm install
npm run dev
```

`npm run dev` compiles the TypeScript and launches Electron. For an installer:

```bash
npm run dist
```

That writes an NSIS installer to `dist_electron/`. It is unsigned, so SmartScreen will
warn on first launch. Click "More info", then "Run anyway", or sign it yourself.

## First run

1. FreeFlow appears in the tray. Click it to open the panel.
2. It downloads whisper.cpp (20MB) and the speech model (about 500MB for the default
   `small.en`). The panel shows progress. This happens once.
3. Windows asks for the microphone the first time you record. If you miss the prompt,
   allow it in Settings, Privacy and security, Microphone, and make sure "Let desktop
   apps access your microphone" is on.
4. Paste a Groq key in Settings if you want cleanup. Without one, FreeFlow inserts the
   raw transcript.

## Settings worth knowing

**Trigger key.** Right Alt by default. Click the key button in Settings and press the
key you want. Raw keycodes differ between keyboards, so it captures the real code
rather than guessing.

**Speech model.** `base.en` is quickest, `small.en` is the default, and
`large-v3-turbo-q5_0` is the most accurate. Transcription runs on the CPU unless you
turn on NVIDIA acceleration, and large is slow enough on a CPU to notice on every take.

**NVIDIA acceleration.** Downloads the CUDA build of whisper.cpp, which is 643MB and
only useful with an NVIDIA card. There is no Vulkan build published for Windows x64, so
AMD and Intel GPUs fall back to the CPU.

**Cleanup with Groq.** Off means raw transcripts, which are usable but keep your filler
words. On sends the transcript, the name of the app you are dictating into, and nothing
else to `api.groq.com`.

## Where your data lives

`%APPDATA%\FreeFlow` (or `%APPDATA%\freeflow-windows` when you run it from source):

- `settings.json`
- `history.json`, the last 200 transcripts
- `stats.json` and `insights.json`, the totals and the per-day record
- `vocabulary.json`, `snippets.json`, `actions.json`, `style.json`
- `credentials.json`, which holds your Groq API key

**The API key is stored in plain text.** Windows Credential Manager would be better and
is on the list, but this is honest about where things stand: anything running as you can
read that file. Use a Groq key you are happy to rotate.

Audio is written to a temporary WAV file for the length of one transcription and deleted
straight after. Nothing else touches the disk.

## How the pieces fit

| Piece | How |
|---|---|
| Global key watch | `uiohook-napi`, a low-level keyboard hook |
| Microphone | Chromium `getUserMedia` in a hidden window, 16kHz mono |
| Speech to text | `whisper.cpp` as a subprocess |
| Cleanup | Groq chat completions, `llama-3.3-70b-versatile` |
| Text insertion | Clipboard plus a synthetic Ctrl+V through a long-lived PowerShell |
| UI | A normal app window, plus two frameless always-on-top windows drawn to look like the Mac notch |

## Known limitations

- **Text insertion uses the clipboard.** Your clipboard is restored about 600ms after
  the paste. Windows has no equivalent of the Accessibility write the Mac build tries
  first, short of a native UI Automation addon.
- **Apps running as administrator do not receive the paste.** A normal process cannot
  send keystrokes to an elevated window. Run FreeFlow as administrator too if you need
  this, with the usual caveats.
- **The overlay is a drawn rectangle, not a real notch.** Windows laptops do not have
  one. It sits at the top centre of the primary display.
- **First recording after boot is slightly slower**, while Windows wakes the microphone.
- English only, matching the Mac build.
- **No meeting recorder.** See above.

## Licences

FreeFlow is MIT. It pulls in, at runtime or build time:

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp), MIT, downloaded on first run
- Whisper models from the `ggerganov/whisper.cpp` repository on Hugging Face, MIT
- [uiohook-napi](https://github.com/SnosMe/uiohook-napi), MIT
- [Electron](https://electronjs.org), MIT
- Icons from [Lucide](https://lucide.dev), ISC, itself a fork of Feather, MIT

No API key ships in this repository, and none ever should. Bring your own.
