import { clipboard } from 'electron';
import { spawn, ChildProcessWithoutNullStreams } from 'node:child_process';

/// Puts text into whatever window is in front, by putting it on the clipboard and
/// sending Ctrl+V.
///
/// The Mac version tries an Accessibility write first, which leaves the clipboard
/// alone. Windows has an equivalent in UI Automation's TextPattern, but reaching it
/// from Node needs a native addon, and Ctrl+V works in every Windows app including
/// Electron ones. So this is the only route for now.
///
/// The dictation stays on the clipboard afterwards. Putting the old contents back
/// on a timer is a race against the paste, which a slow machine can lose, and it
/// takes away the one way to recover when a paste misses: press Ctrl+V yourself.
///
/// Keystrokes go through one long-lived PowerShell process. Starting PowerShell per
/// paste costs a few hundred milliseconds, which is visible when you are waiting to
/// see your words appear.

let shell: ChildProcessWithoutNullStreams | null = null;

/// One line, and it has to be. PowerShell reading commands from stdin treats a
/// statement that spans lines the way its prompt does: it waits for a blank line
/// before running any of it, and swallows every command sent after.
const DECLARE_KEYS =
  'Add-Type -Namespace Win -Name Keys -MemberDefinition \'' +
  '[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, System.UIntPtr extra);' +
  '\'\n';

/// Alt and the Windows key, left and right, as the keyboard hook numbers them.
const MENU_KEYCODES = new Set([56, 3640, 3675, 3676]);

function powershell(): ChildProcessWithoutNullStreams {
  if (shell && !shell.killed) return shell;

  shell = spawn(
    'powershell.exe',
    ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', '-'],
    { windowsHide: true }
  );
  shell.stdin.write('Add-Type -AssemblyName System.Windows.Forms\n');
  shell.stdin.write(DECLARE_KEYS);
  shell.on('exit', () => {
    shell = null;
  });
  return shell;
}

/** Started at launch so the first dictation doesn't pay for PowerShell booting. */
export function warmUp(): void {
  if (process.platform === 'win32') powershell();
}

export function shutdown(): void {
  shell?.kill();
  shell = null;
}

/** Stops a trigger key that is Alt or the Windows key from opening a menu.
 *
 *  Windows treats Alt pressed and released with nothing in between as "focus the
 *  menu bar", and the Windows key the same way as "open Start". The hook only
 *  watches, so the app in front still sees the trigger, and a dictation ended
 *  with the focus in a menu bar instead of the text box the paste was meant for.
 *
 *  Any other key arriving while the trigger is down cancels that. 0xE8 is a key
 *  code assigned to nothing, so it cancels it and does nothing else. */
export function maskMenuKey(triggerKeycode: number): void {
  if (process.platform !== 'win32' || !MENU_KEYCODES.has(triggerKeycode)) return;
  try {
    powershell().stdin.write(
      '[Win.Keys]::keybd_event(0xE8,0,0,[UIntPtr]::Zero);[Win.Keys]::keybd_event(0xE8,0,2,[UIntPtr]::Zero)\n'
    );
  } catch {
    // Best effort. Without it the dictation still happens.
  }
}

export type InjectResult = 'pasted' | 'copied';

export async function insert(text: string): Promise<InjectResult> {
  if (!text) return 'pasted';

  if (process.platform !== 'win32') {
    clipboard.writeText(text);
    return 'copied';
  }

  clipboard.writeText(text);

  try {
    powershell().stdin.write("[System.Windows.Forms.SendKeys]::SendWait('^v')\n");
  } catch {
    // PowerShell is gone or blocked. The text is on the clipboard either way, so
    // say so rather than pretending it landed.
    return 'copied';
  }

  return 'pasted';
}
