# Shows, on a real Windows desktop, what a solo tap of Right Alt does to the window
# in front, and that the mask FreeFlow sends stops it.
#
# A window with a classic menu bar and a text box. For each case: tap Right Alt,
# then paste with Ctrl+V the way inject.ts does, and see whether the text arrived.
#
# Not run on its own. smoke-keys.mjs starts it and supplies the mask through the
# app's real code: this script prints MASK_CASE before the second tap, and expects
# whoever is listening to be watching the keyboard by the time it comes.

param([int]$HoldMs = 120)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Native {
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO info);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
    public int cbSize; public uint flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret;
  }
  public static bool InMenuMode() {
    var info = new GUITHREADINFO(); info.cbSize = Marshal.SizeOf(info);
    return GetGUIThreadInfo(GetCurrentThreadId(), ref info) && (info.flags & 0x4) != 0;
  }
}
'@

$form = New-Object System.Windows.Forms.Form
$form.Text = 'FreeFlow menu mask test'
$form.TopMost = $true
$menu = New-Object System.Windows.Forms.MainMenu
$file = $menu.MenuItems.Add('&File')
[void]$file.MenuItems.Add('E&xit')
$form.Menu = $menu
$box = New-Object System.Windows.Forms.TextBox
$box.Dock = 'Fill'
$box.Multiline = $true
$form.Controls.Add($box)

$EXT = 1; $UP = 2
function Key([byte]$vk, [uint32]$flags) { [Native]::keybd_event($vk, 0, $flags, [UIntPtr]::Zero) }
function Say([string]$line) { [Console]::Out.WriteLine($line); [Console]::Out.Flush() }

$cases = @(
  @{ name = 'Right Alt tapped on its own'; mask = $false },
  @{ name = 'Right Alt tapped, with the mask'; mask = $true }
)
$script:index = 0
$script:step = 0
$script:results = @()
$script:foreground = $false

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 700
$timer.Add_Tick({
  $case = $cases[$script:index]
  switch ($script:step) {
    0 {
      $form.Activate(); [void][Native]::SetForegroundWindow($form.Handle); [void]$box.Focus()
      $box.Text = ''
      [System.Windows.Forms.Clipboard]::SetText('dictated text')
      if ($case.mask) { Say 'MASK_CASE' }
    }
    1 {
      $script:foreground = ([Native]::GetForegroundWindow() -eq $form.Handle)
      if (-not $case.mask) { Say 'WINDOW_UP' }
      Key 0xA5 $EXT
      Start-Sleep -Milliseconds $HoldMs
      Key 0xA5 ($EXT -bor $UP)
    }
    2 {
      $script:inMenu = [Native]::InMenuMode()
      [System.Windows.Forms.SendKeys]::Send('^v')
    }
    3 {
      $script:results += [pscustomobject]@{
        Case = $case.name; Foreground = $script:foreground; MenuTookFocus = $script:inMenu; Pasted = ($box.Text -eq 'dictated text'); Box = $box.Text
      }
      Key 0x1B 0; Key 0x1B $UP   # Esc, to leave the menu if we are in it
    }
    4 {
      $script:index += 1
      $script:step = -1
      if ($script:index -ge $cases.Count) { $timer.Stop(); $form.Close() }
    }
  }
  $script:step += 1
})
$form.Add_Shown({ $timer.Start() })
[System.Windows.Forms.Application]::Run($form)

$script:results | Format-List | Out-String | Write-Host

$bare = $script:results[0]; $masked = $script:results[1]
if (-not $masked.Foreground) { Write-Host '?? the test window never got the foreground, so this run proves nothing'; exit 0 }
if ($bare.MenuTookFocus -or -not $bare.Pasted) { Write-Host '++ without the mask, a solo Right Alt sends the focus to the menu and the paste is lost' }
else { Write-Host '?? without the mask the paste landed anyway on this machine' }
if ($masked.MenuTookFocus -or -not $masked.Pasted) { Write-Host '!! the mask did not keep the focus in the text box'; exit 1 }
Write-Host '++ with the mask, the paste lands in the text box'
