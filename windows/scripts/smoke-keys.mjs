// Drives the real hotkey.ts, inject.ts and foreground.ts against a real window on
// a Windows runner. None of their failures is visible from a Mac: a trigger that
// never fires, a paste that lands in a menu bar, every app reported as "Windows".
//
// Run after `npm run build`:  node scripts/smoke-keys.mjs

import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const { HotkeyMonitor } = await import('../dist/main/hotkey.js');
const inject = await import('../dist/main/inject.js');
const foreground = await import('../dist/main/foreground.js');

const RIGHT_ALT = 3640;
const here = path.dirname(fileURLToPath(import.meta.url));

inject.warmUp();
foreground.warmUp();
// Both shells compile a declaration before they can answer. The app has from
// launch until the first dictation; give the test the same head start.
await new Promise((resolve) => setTimeout(resolve, 4000));

let failed = false;
let frontApp = null;

// Wired the way main.ts wires it. The mask is a keystroke of our own, and the
// monitor has to see through it: taken for a chord, it would cancel the press.
const seen = { presses: 0, releases: 0 };
const monitor = new HotkeyMonitor(RIGHT_ALT, {
  onDown: (keycode) => inject.maskMenuKey(keycode),
  onPress: () => (seen.presses += 1),
  onRelease: () => (seen.releases += 1),
  onEscape: () => {},
});

const window = spawn(
  'powershell.exe',
  ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(here, 'smoke-menu-mask.ps1'),
    '-HoldMs', process.env.HOLD_MS ?? '120'],
  { windowsHide: false }
);

let pending = '';
window.stdout.on('data', (chunk) => {
  pending += chunk.toString();
  let newline;
  while ((newline = pending.indexOf('\n')) !== -1) {
    const line = pending.slice(0, newline).trimEnd();
    pending = pending.slice(newline + 1);
    if (line === 'MASK_CASE') monitor.start();
    else if (line === 'WINDOW_UP') frontApp = foreground.foregroundApp();
    else if (line) console.log(line);
  }
});
window.stderr.on('data', (chunk) => console.log(chunk.toString().trimEnd()));

const code = await new Promise((resolve) => window.on('exit', resolve));
if (code !== 0) failed = true;

monitor.stop();

console.log('== the trigger, with the mask in the way ==');
console.log(`   ${seen.presses} press, ${seen.releases} release`);
if (seen.presses !== 1 || seen.releases !== 1) {
  console.log('!! one tap of Right Alt should be exactly one press and one release');
  failed = true;
} else {
  console.log('++ the monitor still sees the tap');
}

console.log('\n== which app is in front ==');
const app = frontApp ? await frontApp : { process: '', name: '' };
console.log(`   process "${app.process}", shown as "${app.name}"`);
if (!/^powershell\.exe$/i.test(app.process)) {
  console.log('!! expected the test window, which belongs to powershell.exe');
  failed = true;
} else {
  console.log('++ the foreground lookup answers');
}

inject.shutdown();
foreground.shutdown();
process.exit(failed ? 1 : 0);
