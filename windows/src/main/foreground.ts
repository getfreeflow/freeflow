import { spawn, ChildProcessWithoutNullStreams } from 'node:child_process';

/// Which app is in front, so History can say where a dictation went and the cleanup
/// prompt can match the app's register.
///
/// Windows has no API for this in Electron, so it goes through the same long-lived
/// PowerShell process trick as text insertion: declare GetForegroundWindow once,
/// then ask it per take. Best effort, and the answer is never waited on for long.

let shell: ChildProcessWithoutNullStreams | null = null;
let buffer = '';
let pending: ((value: string) => void) | null = null;

const DECLARE = `Add-Type -Namespace Win -Name Api -MemberDefinition '
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
'
`;

function shellProcess(): ChildProcessWithoutNullStreams {
  if (shell && !shell.killed) return shell;

  shell = spawn('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', '-'], {
    windowsHide: true,
  });
  shell.stdin.write(DECLARE);
  shell.stdout.on('data', (chunk: Buffer) => {
    buffer += chunk.toString();
    const newline = buffer.indexOf('\n');
    if (newline === -1 || !pending) return;
    const line = buffer.slice(0, newline).trim();
    buffer = buffer.slice(newline + 1);
    const resolve = pending;
    pending = null;
    resolve(line);
  });
  shell.on('exit', () => {
    shell = null;
    buffer = '';
  });
  return shell;
}

export function warmUp(): void {
  if (process.platform === 'win32') shellProcess();
}

export function shutdown(): void {
  shell?.kill();
  shell = null;
}

export interface ForegroundApp {
  /** Executable name, e.g. "slack.exe". Matches the style hint table. */
  process: string;
  /** What to show a person, e.g. "Slack". */
  name: string;
}

const UNKNOWN: ForegroundApp = { process: '', name: 'Windows' };

export async function foregroundApp(): Promise<ForegroundApp> {
  if (process.platform !== 'win32') return UNKNOWN;

  try {
    const line = await Promise.race([
      new Promise<string>((resolve) => {
        pending = resolve;
        shellProcess().stdin.write(
          '$h=[Win.Api]::GetForegroundWindow(); [void][Win.Api]::GetWindowThreadProcessId($h,[ref]$p);' +
            '$proc=Get-Process -Id $p -ErrorAction SilentlyContinue;' +
            'Write-Output ("{0}|{1}" -f ($proc.ProcessName + ".exe"), $proc.MainWindowTitle)\n'
        );
      }),
      // Never hold up a dictation for this.
      new Promise<string>((resolve) => setTimeout(() => resolve(''), 400)),
    ]);

    pending = null;
    if (!line) return UNKNOWN;

    const [executable = '', title = ''] = line.split('|');
    if (!executable || executable === '.exe') return UNKNOWN;

    return {
      process: executable,
      name: friendlyName(executable, title),
    };
  } catch {
    return UNKNOWN;
  }
}

/** Window titles are long and end with the app name ("… - Slack"), so the tail is
 *  usually the nicest label. Falls back to the executable without its extension. */
function friendlyName(executable: string, title: string): string {
  const tail = title.split(' - ').pop()?.trim();
  if (tail && tail.length > 1 && tail.length <= 30) return tail;
  const base = executable.replace(/\.exe$/i, '');
  return base.charAt(0).toUpperCase() + base.slice(1);
}
