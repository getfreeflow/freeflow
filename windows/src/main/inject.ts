import { clipboard } from 'electron';
import { spawn, ChildProcessWithoutNullStreams } from 'node:child_process';

/// Puts text into whatever window is in front, by putting it on the clipboard and
/// sending Ctrl+V.
///
/// The Mac version tries an Accessibility write first, which leaves the clipboard
/// alone. Windows has an equivalent in UI Automation's TextPattern, but reaching it
/// from Node needs a native addon, and Ctrl+V works in every Windows app including
/// Electron ones. So this is the only route for now, and the clipboard is put back
/// afterwards.
///
/// Keystrokes go through one long-lived PowerShell process. Starting PowerShell per
/// paste costs a few hundred milliseconds, which is visible when you are waiting to
/// see your words appear.

let shell: ChildProcessWithoutNullStreams | null = null;

function powershell(): ChildProcessWithoutNullStreams {
  if (shell && !shell.killed) return shell;

  shell = spawn(
    'powershell.exe',
    ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', '-'],
    { windowsHide: true }
  );
  shell.stdin.write('Add-Type -AssemblyName System.Windows.Forms\n');
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

export type InjectResult = 'pasted' | 'copied';

export async function insert(text: string): Promise<InjectResult> {
  if (!text) return 'pasted';

  if (process.platform !== 'win32') {
    await clipboard.writeText(text);
    return 'copied';
  }

  const previous = await clipboard.readText();
  await clipboard.writeText(text);

  try {
    powershell().stdin.write("[System.Windows.Forms.SendKeys]::SendWait('^v')\n");
  } catch {
    // PowerShell is gone or blocked. The text is on the clipboard either way, so
    // say so rather than pretending it landed.
    return 'copied';
  }

  // Put back what was there, once the paste has had time to happen.
  setTimeout(() => {
    if (previous) void clipboard.writeText(previous);
  }, 600);

  return 'pasted';
}
