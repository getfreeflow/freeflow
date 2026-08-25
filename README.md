# FreeFlow

Voice dictation for macOS that runs on your own machine. Hold a key, talk, and the text
appears wherever your cursor is.

Transcription happens locally with a Whisper model. No audio leaves your Mac, there's no
account, and nothing is metered. An optional cleanup pass turns the raw transcript into text
you can actually send, using an API key you supply.

## What it does

**Dictation.** Hold the trigger key and talk. Release, and the text is inserted at your
cursor. Tap the key instead of holding it to latch recording on; a small pill appears at the
bottom of the screen with a discard and an insert button. `esc` throws the take away.

**Commands.** Select text anywhere, hold the command key, and say what you want done to it.
"Cut this in half." "Make these bullets." The result replaces the selection. With nothing
selected you get an answer instead, inserted at the cursor.

**Meetings.** Records both sides of a call from your Mac's audio output. Nothing joins the
call and no one is notified. Audio is transcribed on-device and written up with the points,
decisions and follow-ups. You can ask questions about anything you recorded.

**Style.** Per-app rules for how it writes, because a line in a chat window and a paragraph
in a document shouldn't sound the same. Ships with defaults; all editable.

**Vocabulary.** The words it keeps getting wrong: your name, your colleagues, product names,
acronyms.

**Snippets.** Say two words, insert a paragraph. Expanded before cleanup runs, so the result
still gets shaped for wherever it's going.

**Actions.** Saved instructions you can apply to any text, from inside the app or by name
while dictating. Shorten, Formal, Friendly, Bullets, Fix grammar, Summarize, and your own.

**Scratchpad.** A page that's always open for thoughts without a home yet.

**Insights.** What you dictated per day, how fast you speak, where the words went.

Plus searchable history, launch at login, three model sizes, and a fully offline mode.

## Requirements

macOS 14 or later. Apple Silicon recommended. To build you need Xcode 15+ and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Build

```bash
git clone https://github.com/YOUR_USERNAME/freeflow.git
```

```bash
cd freeflow && xcodegen generate && open FreeFlow.xcodeproj
```

Press Run, then drag the built app to `/Applications`. The `.xcodeproj` is generated rather
than committed, so the checkout stays clean.

## Making permissions stick

Worth doing before you grant anything.

By default the app is ad-hoc signed, which needs no setup but has an unpleasant consequence.
An ad-hoc signature is a hash of the binary, so it changes on every build, and macOS
identifies apps to TCC (Accessibility, Input Monitoring, Microphone) by that signature. Every
rebuild looks like a new app, and the permissions you granted belong to a build that no
longer exists. The switches stay on in System Settings while the running app is refused.
Reinstalling is the cause, not the cure.

Signing with a certificate replaces that hash with the certificate's, which never changes.

Create one. It's self-signed and never leaves your Mac:

```bash
printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=FreeFlow Local Signing\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > /tmp/ff.cnf
```

```bash
openssl req -newkey rsa:2048 -nodes -keyout /tmp/ff-key.pem -x509 -days 7300 -out /tmp/ff-cert.pem -config /tmp/ff.cnf && openssl pkcs12 -export -inkey /tmp/ff-key.pem -in /tmp/ff-cert.pem -out /tmp/ff.p12 -passout pass:freeflow -name "FreeFlow Local Signing" && security import /tmp/ff.p12 -k ~/Library/Keychains/login.keychain-db -P freeflow -T /usr/bin/codesign -A
```

Importing sets the key's ACL but not its partition list, which is a separate gate. Without
this next step `codesign` is refused with `errSecInternalComponent`. It will ask for your
login password:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "FreeFlow Local Signing" ~/Library/Keychains/login.keychain-db
```

Point the build at it:

```bash
echo 'CODE_SIGN_IDENTITY = FreeFlow Local Signing' > Support/Signing.local.xcconfig && xcodegen generate
```

That file is gitignored, so nothing machine-specific gets committed. Rebuild and check:

```bash
codesign -d -r- /Applications/FreeFlow.app
```

You want `identifier "com.freeflow.FreeFlow" and certificate leaf = H"..."`. If you see
`cdhash` instead, it's still ad-hoc.

Finally, clear the entries the old ad-hoc builds left behind. There is one per past build,
and they are why System Settings can show a permission as granted while the app disagrees:

```bash
for s in Accessibility ListenEvent Microphone; do tccutil reset $s com.freeflow.FreeFlow; done
```

Grant the three permissions once after that and you're done with this permanently.

The certificate is untrusted by Gatekeeper standards, which is fine here. `codesign` accepts
it and TCC only cares that the leaf hash is stable. It is not a substitute for a Developer ID
if you ever want to hand the app to someone else.

## Setting it up

Pick your keys. `fn` is the default because nothing competes for it. Right-Option and
Right-Control also work well.

If you pick `fn`, take it back from macOS first. It's assigned to Dictation or Emoji by
default and that assignment wins:

> System Settings → Keyboard → "Press 🌐 key to" → Do Nothing

Grant access to the Microphone, Accessibility (to place text into other apps), and Input
Monitoring (to see the trigger key). Meetings additionally needs Screen Recording, which is
how macOS gates system audio; it's requested the first time you record one.

Pick a model. Downloaded once with a progress readout, then cached.

| Model | Size | |
|---|---|---|
| `large-v3-turbo` | ~1.5 GB | Most accurate, still fast on Apple Silicon |
| `small.en` | ~500 MB | Lighter, stumbles more on names |
| `base.en` | ~150 MB | Fastest and roughest, for older hardware |

Optionally add a key. Cleanup, commands, actions and meeting summaries go through
[Groq](https://console.groq.com/keys), which has a free tier and needs no card. Without one
dictation still works; you get the transcript as spoken.

## Where your key is stored

In `~/Library/Application Support/FreeFlow/credentials.json`, owner-only (`0600`). Never in
this repository, never in a plist, never in the app bundle. There are no credentials in this
codebase at all, which is what makes it safe to fork.

It is not encrypted at rest. Any process running as your user can read that file. This was a
deliberate trade. macOS ties Keychain access to an app's code signature, and a project you
build yourself gets a new signature on every rebuild, so the Keychain treats each build as a
different app and asks for your login password on launch, repeatedly. For a build-it-yourself
app that isn't usable. If you'd rather have Keychain storage and don't mind re-authorising
after each rebuild, `SecretFile` in
[CredentialStore.swift](Sources/Core/CredentialStore.swift) is the only thing to change.

Turn Cleanup off in Settings and the app makes no network requests at all.

## How it works

```
key down ──▶ AudioRecorder      AVAudioEngine → 16 kHz mono Float32
key up   ──▶ Transcriber        WhisperKit, on-device, streaming partial text
             ├▶ Vocabulary      your spellings restored
             ├▶ Snippets        spoken shorthand expanded
             ├▶ GroqClient      cleanup via your Style rules, or a command
             └▶ TextInjector    Accessibility write, else clipboard + ⌘V
```

Three things in the source worth knowing about:

- Modifier keys emit no key event, only a flag change, so
  [`HotkeyMonitor`](Sources/Core/HotkeyMonitor.swift) watches `.flagsChanged` rather than
  `.keyDown`.
- Arrow keys set the fn mask too, and the two Option keys share a flag. So matching happens on
  the keycode of the physical key that moved, and the flag only decides up versus down.
- Trigger keys are keys people type with. Firing on every Command-down would trigger on ⌘C, so
  a press only counts once it has been held alone past 120 ms. Add a second key and it's a
  chord and gets ignored. A fast solo tap still latches.

The event tap is `.listenOnly`, so it observes without consuming and nothing you already use
breaks. Insertion tries a direct Accessibility write first, which leaves the clipboard
untouched, and falls back to clipboard plus synthetic ⌘V, which works essentially everywhere
including Electron apps. If nothing focused can accept text, the transcript is left on the
clipboard rather than pasted into nowhere.

Meetings uses [ScreenCaptureKit](Sources/Core/Notetaker.swift), the only sanctioned route to
system audio on current macOS. A 2×2 video stream is requested because a content filter is
mandatory; the video is discarded.

## Rough edges

- Meeting transcripts have no speaker labels. Both sides land on one mixed track, so the
  summary infers who spoke from context rather than knowing.
- Launch at login requires the app to live in `/Applications`.
- The first launch is slow while the model downloads. Every one after is not.
- Groq's free tier is rate limited. On a 429 you get the raw transcript rather than an error.

## Not built

Any language other than English, iOS or Android, team features.

## Contributing

Issues and pull requests welcome. This is a personal project released for free. There's no
company behind it, no paid tier planned, and no telemetry of any kind.

## Credits

Speech recognition by [WhisperKit](https://github.com/argmaxinc/WhisperKit) from Argmax.
Interface tokens adapted from [shadcn/ui](https://ui.shadcn.com). Language model calls go to
[Groq](https://groq.com).

Independent and unaffiliated. Not connected to, sponsored by, or endorsed by any commercial
dictation product.

## License

MIT, see [LICENSE](LICENSE).
